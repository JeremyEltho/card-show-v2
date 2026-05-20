from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.services.inventory_service import list_items, create_item, update_item, delete_item
from app.schemas.inventory import (
    InventoryListResponse, InventoryItemOut,
    CreateInventoryRequest, UpdateInventoryRequest,
    VALID_STATUSES, VALID_CONDITIONS,
)

router = APIRouter(prefix="/inventory", tags=["inventory"])


@router.get("", response_model=InventoryListResponse)
async def get_inventory(
    status: str | None = Query(None),
    card_id: str | None = Query(None),
    sort: str = Query("acquired_at", pattern="^(acquired_at|created_at|purchase_price|sale_price)$"),
    order: str = Query("desc", pattern="^(asc|desc)$"),
    page: int = Query(1, ge=1),
    limit: int = Query(25, ge=1, le=100),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if status and status not in VALID_STATUSES:
        raise HTTPException(status_code=400, detail=f"Invalid status. Must be one of: {VALID_STATUSES}")
    result = await list_items(user.id, status, card_id, sort, order, page, limit, db)
    return InventoryListResponse(**result)


@router.post("", response_model=InventoryItemOut, status_code=status.HTTP_201_CREATED)
async def add_to_inventory(
    body: CreateInventoryRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if body.status not in VALID_STATUSES:
        raise HTTPException(status_code=400, detail=f"Invalid status")
    if body.condition not in VALID_CONDITIONS:
        raise HTTPException(status_code=400, detail=f"Invalid condition")
    item = await create_item(user.id, body, db)
    return InventoryItemOut(**item)


@router.patch("/{item_id}", response_model=InventoryItemOut)
async def update_inventory_item(
    item_id: str,
    body: UpdateInventoryRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if body.status and body.status not in VALID_STATUSES:
        raise HTTPException(status_code=400, detail="Invalid status")
    item = await update_item(item_id, user.id, body, db)
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    return InventoryItemOut(**item)


@router.delete("/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_inventory_item(
    item_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    deleted = await delete_item(item_id, user.id, db)
    if not deleted:
        raise HTTPException(status_code=404, detail="Item not found")
