from datetime import datetime
from pydantic import BaseModel


VALID_STATUSES = {"holding", "bought", "sold", "traded", "wishlist"}
VALID_CONDITIONS = {"mint", "near_mint", "lightly_played", "moderately_played", "heavily_played", "damaged"}


class CardSummary(BaseModel):
    card_id: str
    name: str | None = None
    set_name: str | None = None
    image_url_sm: str | None = None
    market_price: float | None = None


class InventoryItemOut(BaseModel):
    id: str
    card_id: str
    card: CardSummary | None = None
    status: str
    condition: str
    quantity: int
    purchase_price: float | None = None
    sale_price: float | None = None
    market_price_at_scan: float | None = None
    unrealized_gain: float | None = None
    notes: str | None = None
    source_location: str | None = None
    acquired_at: str
    sold_at: str | None = None
    created_at: str
    updated_at: str
    client_id: str | None = None


class InventoryListResponse(BaseModel):
    items: list[InventoryItemOut]
    total: int
    page: int
    pages: int


class CreateInventoryRequest(BaseModel):
    card_id: str
    status: str = "holding"
    condition: str = "near_mint"
    quantity: int = 1
    purchase_price: float | None = None
    sale_price: float | None = None
    market_price_at_scan: float | None = None
    notes: str | None = None
    source_location: str | None = None
    acquired_at: datetime | None = None
    payment_method: str | None = None
    client_id: str | None = None


class UpdateInventoryRequest(BaseModel):
    status: str | None = None
    condition: str | None = None
    quantity: int | None = None
    purchase_price: float | None = None
    sale_price: float | None = None
    notes: str | None = None
    source_location: str | None = None
    sold_at: datetime | None = None
