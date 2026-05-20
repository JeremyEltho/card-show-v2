from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.services.inventory_service import create_item, update_item, delete_item
from app.schemas.inventory import CreateInventoryRequest, UpdateInventoryRequest
from app.schemas.sync import SyncRequest, SyncResult

router = APIRouter(prefix="/sync", tags=["sync"])


@router.post("", response_model=SyncResult)
async def sync_offline_queue(
    body: SyncRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    processed = 0
    failed = []

    for op in body.operations:
        try:
            if op.type == "create_inventory":
                payload = {**op.payload, "client_id": op.client_id}
                req = CreateInventoryRequest(**payload)
                await create_item(user.id, req, db)
                processed += 1

            elif op.type == "update_inventory":
                item_id = op.payload.pop("id", None)
                if item_id:
                    req = UpdateInventoryRequest(**op.payload)
                    await update_item(item_id, user.id, req, db)
                    processed += 1
                else:
                    failed.append({"client_id": op.client_id, "error": "Missing item id"})

            elif op.type == "delete_inventory":
                item_id = op.payload.get("id")
                if item_id:
                    await delete_item(item_id, user.id, db)
                    processed += 1
                else:
                    failed.append({"client_id": op.client_id, "error": "Missing item id"})

        except Exception as e:
            failed.append({"client_id": op.client_id, "error": str(e)})

    return SyncResult(processed=processed, failed=failed)
