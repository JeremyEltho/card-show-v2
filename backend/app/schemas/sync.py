from pydantic import BaseModel


class SyncOperation(BaseModel):
    client_id: str
    type: str  # create_inventory | update_inventory | delete_inventory
    payload: dict
    client_timestamp: str | None = None


class SyncRequest(BaseModel):
    operations: list[SyncOperation]


class SyncResult(BaseModel):
    processed: int
    failed: list[dict] = []
