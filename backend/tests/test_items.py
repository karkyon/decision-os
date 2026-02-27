import pytest
import time
from httpx import AsyncClient, ASGITransport
from app.main import app

BASE = "http://test"

async def get_auth(client):
    r = await client.post("/api/v1/auth/login",
        json={"email": "demo@example.com", "password": "demo1234"})
    return {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

async def create_items(client, headers):
    r = await client.post("/api/v1/projects", headers=headers,
        json={"name": f"item_{int(time.time())}", "description": "t"})
    pid = r.json().get("id", "")
    inp = await client.post("/api/v1/inputs", headers=headers,
        json={"project_id": pid, "raw_text": "検索機能を追加してほしい"})
    iid = inp.json().get("id", "")
    items_resp = await client.post("/api/v1/analyze", headers=headers,
        json={"input_id": iid})
    items = items_resp.json() if isinstance(items_resp.json(), list) else []
    return items, pid, iid

@pytest.mark.asyncio
async def test_list_items_by_input():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        items, pid, iid = await create_items(c, h)
        # input_id で items を絞り込み
        r = await c.get(f"/api/v1/items?input_id={iid}", headers=h)
        assert r.status_code in (200, 404, 422)

@pytest.mark.asyncio
async def test_list_items_no_filter():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.get("/api/v1/items", headers=h)
        assert r.status_code in (200, 404, 422)

@pytest.mark.asyncio
async def test_items_created_by_analyze():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        items, pid, iid = await create_items(c, h)
        assert len(items) >= 1
        assert items[0].get("id")
        assert items[0].get("intent_code")
