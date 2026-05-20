"""
Inventory CRUD with idempotency, soft-delete, and auto transaction ledger.
"""
import uuid
from datetime import datetime, timezone

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_

from app.models.inventory import InventoryItem, Transaction
from app.models.card_cache import CardCache, PriceCache
from app.schemas.inventory import CreateInventoryRequest, UpdateInventoryRequest


def _dt_str(dt: datetime | None) -> str | None:
    if not dt:
        return None
    if dt.tzinfo is None:
        return dt.isoformat() + "Z"
    return dt.isoformat()


async def _enrich_with_card(item: InventoryItem, db: AsyncSession) -> dict:
    card_row = await db.get(CardCache, item.card_id)
    price_row = await db.get(PriceCache, item.card_id)
    market_price = price_row.market_price if price_row else None

    unrealized = None
    if item.status in ("holding", "bought") and item.purchase_price and market_price:
        unrealized = round((market_price - item.purchase_price) * item.quantity, 2)

    card_summary = {
        "card_id": item.card_id,
        "name": card_row.name if card_row else None,
        "set_name": card_row.set_name if card_row else None,
        "image_url_sm": card_row.image_url_sm if card_row else None,
        "market_price": market_price,
    }

    return {
        "id": item.id,
        "card_id": item.card_id,
        "card": card_summary,
        "status": item.status,
        "condition": item.condition,
        "quantity": item.quantity,
        "purchase_price": item.purchase_price,
        "sale_price": item.sale_price,
        "market_price_at_scan": item.market_price_at_scan,
        "unrealized_gain": unrealized,
        "notes": item.notes,
        "source_location": item.source_location,
        "acquired_at": _dt_str(item.acquired_at),
        "sold_at": _dt_str(item.sold_at),
        "created_at": _dt_str(item.created_at),
        "updated_at": _dt_str(item.updated_at),
        "client_id": item.client_id,
    }


async def list_items(
    user_id: str,
    status_filter: str | None,
    card_id_filter: str | None,
    sort: str,
    order: str,
    page: int,
    limit: int,
    db: AsyncSession,
) -> dict:
    conditions = [
        InventoryItem.user_id == user_id,
        InventoryItem.deleted_at.is_(None),
    ]
    if status_filter:
        conditions.append(InventoryItem.status == status_filter)
    if card_id_filter:
        conditions.append(InventoryItem.card_id == card_id_filter)

    count_q = select(func.count()).select_from(InventoryItem).where(and_(*conditions))
    total = (await db.execute(count_q)).scalar_one()

    sort_col = getattr(InventoryItem, sort, InventoryItem.acquired_at)
    order_col = sort_col.desc() if order == "desc" else sort_col.asc()

    items_q = (
        select(InventoryItem)
        .where(and_(*conditions))
        .order_by(order_col)
        .offset((page - 1) * limit)
        .limit(limit)
    )
    rows = (await db.execute(items_q)).scalars().all()

    enriched = []
    for row in rows:
        enriched.append(await _enrich_with_card(row, db))

    pages = (total + limit - 1) // limit if total > 0 else 1
    return {"items": enriched, "total": total, "page": page, "pages": pages}


async def create_item(user_id: str, body: CreateInventoryRequest, db: AsyncSession) -> dict:
    # Idempotency: if client_id exists, return existing item
    if body.client_id:
        result = await db.execute(
            select(InventoryItem).where(InventoryItem.client_id == body.client_id)
        )
        existing = result.scalar_one_or_none()
        if existing:
            return await _enrich_with_card(existing, db)

    now = datetime.now(timezone.utc)
    item = InventoryItem(
        user_id=user_id,
        card_id=body.card_id,
        status=body.status,
        condition=body.condition,
        quantity=body.quantity,
        purchase_price=body.purchase_price,
        sale_price=body.sale_price,
        market_price_at_scan=body.market_price_at_scan,
        notes=body.notes,
        source_location=body.source_location,
        acquired_at=body.acquired_at or now,
        sold_at=now if body.status == "sold" else None,
        created_at=now,
        updated_at=now,
        client_id=body.client_id,
    )
    db.add(item)
    await db.flush()

    # Auto-create transaction record
    tx_type = "purchase" if body.status in ("bought", "holding") else (
        "sale" if body.status == "sold" else
        "trade_in" if body.status == "traded" else None
    )
    tx_price = body.purchase_price or body.sale_price or 0.0
    if tx_type and tx_price > 0:
        tx_client_id = str(uuid.uuid4()) if body.client_id else None
        db.add(Transaction(
            user_id=user_id,
            inventory_item_id=item.id,
            type=tx_type,
            price=tx_price,
            quantity=body.quantity,
            payment_method=body.payment_method,
            location=body.source_location,
            client_id=tx_client_id,
        ))

    await db.commit()
    return await _enrich_with_card(item, db)


async def update_item(
    item_id: str, user_id: str, body: UpdateInventoryRequest, db: AsyncSession
) -> dict | None:
    result = await db.execute(
        select(InventoryItem).where(
            InventoryItem.id == item_id,
            InventoryItem.user_id == user_id,
            InventoryItem.deleted_at.is_(None),
        )
    )
    item = result.scalar_one_or_none()
    if not item:
        return None

    prev_status = item.status

    if body.status is not None:
        item.status = body.status
    if body.condition is not None:
        item.condition = body.condition
    if body.quantity is not None:
        item.quantity = body.quantity
    if body.purchase_price is not None:
        item.purchase_price = body.purchase_price
    if body.sale_price is not None:
        item.sale_price = body.sale_price
    if body.notes is not None:
        item.notes = body.notes
    if body.source_location is not None:
        item.source_location = body.source_location
    if body.sold_at is not None:
        item.sold_at = body.sold_at

    item.updated_at = datetime.now(timezone.utc)

    # Auto-create sale transaction when status changes to sold
    if prev_status != "sold" and item.status == "sold" and item.sale_price:
        if not item.sold_at:
            item.sold_at = datetime.now(timezone.utc)
        db.add(Transaction(
            user_id=user_id,
            inventory_item_id=item.id,
            type="sale",
            price=item.sale_price,
            quantity=item.quantity,
        ))

    await db.commit()
    return await _enrich_with_card(item, db)


async def delete_item(item_id: str, user_id: str, db: AsyncSession) -> bool:
    result = await db.execute(
        select(InventoryItem).where(
            InventoryItem.id == item_id,
            InventoryItem.user_id == user_id,
            InventoryItem.deleted_at.is_(None),
        )
    )
    item = result.scalar_one_or_none()
    if not item:
        return False
    item.deleted_at = datetime.now(timezone.utc)
    await db.commit()
    return True
