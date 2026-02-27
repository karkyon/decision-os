import pytest
import asyncio
from httpx import AsyncClient, ASGITransport
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.main import app
from app.db.session import get_db
import os

PROD_DB_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql://dev:devpass_2ed89487@localhost:5439/decisionos"
)

engine = create_engine(PROD_DB_URL)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()

app.dependency_overrides[get_db] = override_get_db

@pytest.fixture(scope="session")
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()

@pytest.fixture(scope="module")
async def client():
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test"
    ) as c:
        yield c

@pytest.fixture(scope="module")
async def auth_token(client):
    resp = await client.post("/api/v1/auth/login", json={
        "email": "demo@example.com",
        "password": "demo1234"
    })
    return resp.json().get("access_token", "")

@pytest.fixture(scope="module")
async def auth_headers(auth_token):
    return {"Authorization": f"Bearer {auth_token}"}
