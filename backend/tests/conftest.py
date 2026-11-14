# tests/conftest.py
import pytest
from httpx import AsyncClient, ASGITransport
from sqlalchemy import create_engine
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.pool import NullPool
from starlette.testclient import TestClient

from app.main import app
from app.core.database import Base, get_db
from app.core.config import settings

# 1. Synchronous engine for session-level setup/teardown (drops and creates tables once)
sync_database_url = settings.DATABASE_URL.replace("postgresql+asyncpg://", "postgresql+psycopg2://")
sync_engine = create_engine(sync_database_url)


@pytest.fixture(scope="session", autouse=True)
def setup_db():
    Base.metadata.drop_all(bind=sync_engine)
    Base.metadata.create_all(bind=sync_engine)
    yield
    Base.metadata.drop_all(bind=sync_engine)


# 2. Asynchronous engine for async (httpx) test execution
engine = create_async_engine(settings.DATABASE_URL, echo=False, future=True)
TestingSessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False, autoflush=False)


@pytest.fixture
async def override_get_db():
    """
    Provide an isolated database session per test using a nested transaction
    that rolls back automatically afterward, preventing cross-test pollution.
    """
    async with engine.connect() as connection:
        async with connection.begin() as transaction:
            async with TestingSessionLocal(bind=connection) as session:
                # Override commit to flush instead, preventing premature transaction closure
                async def override_commit():
                    await session.flush()
                session.commit = override_commit

                try:
                    yield session
                finally:
                    await session.close()
                    if transaction.is_active:
                        await transaction.rollback()


@pytest.fixture
async def async_client(override_get_db):
    # Wrap the session yield in a proper async generator function for FastAPI dependency injection
    async def _override_get_db():
        yield override_get_db

    app.dependency_overrides[get_db] = _override_get_db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()


# 3. Engine + client for sync Starlette TestClient tests (websockets).
#    TestClient runs the app on its own event loop in a background thread, so
#    pooled asyncpg connections must never be reused across clients -> NullPool.
ws_engine = create_async_engine(settings.DATABASE_URL, echo=False, poolclass=NullPool)
WsSessionLocal = async_sessionmaker(ws_engine, class_=AsyncSession, expire_on_commit=False)


@pytest.fixture
def sync_client():
    async def _get_db():
        async with WsSessionLocal() as session:
            yield session

    app.dependency_overrides[get_db] = _get_db
    with TestClient(app) as client:
        yield client
    app.dependency_overrides.clear()