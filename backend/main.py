from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from app.core.config import get_settings
from app.core.database import engine, Base
from app.api.routes import auth, cards, sets, inventory, analytics, scan, sync

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Create all tables on startup (Alembic handles migrations in production)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        # Create FTS5 virtual table for card name search if it doesn't exist
        await conn.execute(text(
            "CREATE VIRTUAL TABLE IF NOT EXISTS card_fts "
            "USING fts5(card_id UNINDEXED, name, content='card_cache', content_rowid='rowid')"
        ))
    yield


app = FastAPI(
    title="PokeScan API",
    description="Pokémon card scanning and inventory platform",
    version="2.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/api/v1")
app.include_router(cards.router, prefix="/api/v1")
app.include_router(sets.router, prefix="/api/v1")
app.include_router(inventory.router, prefix="/api/v1")
app.include_router(analytics.router, prefix="/api/v1")
app.include_router(scan.router, prefix="/api/v1")
app.include_router(sync.router, prefix="/api/v1")


@app.get("/health")
async def health():
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
        db_status = "connected"
    except Exception as e:
        db_status = f"error: {e}"
    return {"status": "ok", "db": db_status, "version": "2.0.0"}
