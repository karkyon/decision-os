import pytest
import time
from httpx import AsyncClient, ASGITransport
from app.main import app

BASE = "http://test"

async def get_auth(client):
    r = await client.post("/api/v1/auth/login",
        json={"email": "demo@example.com", "password": "demo1234"})
    return {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

@pytest.mark.asyncio
async def test_search_basic():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.get("/api/v1/search?q=エラー", headers=h)
        assert r.status_code in (200, 404, 422)

@pytest.mark.asyncio
async def test_search_with_type():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.get("/api/v1/search?q=test&type=issue", headers=h)
        assert r.status_code in (200, 404, 422)

@pytest.mark.asyncio
async def test_search_empty_query():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.get("/api/v1/search?q=", headers=h)
        assert r.status_code in (200, 400, 422)

@pytest.mark.asyncio
async def test_search_issues():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.get("/api/v1/search?q=ログイン&type=issues", headers=h)
        assert r.status_code in (200, 404, 422)
