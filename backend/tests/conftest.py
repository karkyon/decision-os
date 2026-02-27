import pytest
import asyncio
from httpx import AsyncClient, ASGITransport
from app.main import app

# pytest-asyncio 0.23+ では event_loop fixture のカスタム定義は不要
# asyncio_mode=auto（pytest.ini で設定済み）に任せる

BASE_URL = "http://localhost:8089/api/v1"

@pytest.fixture(scope="function")
async def client():
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test"
    ) as c:
        yield c

@pytest.fixture(scope="function")
async def auth_token(client):
    resp = await client.post("/api/v1/auth/login", json={
        "email": "demo@example.com",
        "password": "demo1234"
    })
    data = resp.json()
    return data.get("access_token", "")

@pytest.fixture(scope="function")
async def auth_headers(auth_token):
    return {"Authorization": f"Bearer {auth_token}"}
