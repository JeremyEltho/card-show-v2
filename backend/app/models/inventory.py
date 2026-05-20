import uuid
from datetime import datetime, timezone
from sqlalchemy import String, DateTime, Integer, Float, Text, Boolean
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base


class InventoryItem(Base):
    __tablename__ = "inventory_items"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id: Mapped[str] = mapped_column(String, index=True, nullable=False)
    card_id: Mapped[str] = mapped_column(String, index=True, nullable=False)

    # status: holding | bought | sold | traded | wishlist
    status: Mapped[str] = mapped_column(String, default="holding", nullable=False)
    # condition: mint | near_mint | lightly_played | moderately_played | heavily_played | damaged
    condition: Mapped[str] = mapped_column(String, default="near_mint", nullable=False)
    quantity: Mapped[int] = mapped_column(Integer, default=1, nullable=False)

    purchase_price: Mapped[float | None] = mapped_column(Float)
    sale_price: Mapped[float | None] = mapped_column(Float)
    market_price_at_scan: Mapped[float | None] = mapped_column(Float)

    notes: Mapped[str | None] = mapped_column(Text)
    source_location: Mapped[str | None] = mapped_column(String)

    acquired_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    sold_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # Idempotency key — iOS generates before sending; prevents duplicate on retry
    client_id: Mapped[str | None] = mapped_column(String, unique=True)


class Transaction(Base):
    __tablename__ = "transactions"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id: Mapped[str] = mapped_column(String, index=True, nullable=False)
    inventory_item_id: Mapped[str | None] = mapped_column(String)

    # type: purchase | sale | trade_in | trade_out | price_adjustment
    type: Mapped[str] = mapped_column(String, nullable=False)
    price: Mapped[float] = mapped_column(Float, nullable=False)
    quantity: Mapped[int] = mapped_column(Integer, default=1)
    payment_method: Mapped[str | None] = mapped_column(String)
    location: Mapped[str | None] = mapped_column(String)
    notes: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    client_id: Mapped[str | None] = mapped_column(String, unique=True)
