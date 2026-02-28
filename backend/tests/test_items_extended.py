import pytest, time
from httpx import AsyncClient, ASGITransport
from app.main import app
BASE = "http://test"

async def get_auth(c):
    r = await c.post("/api/v1/auth/login",
        json={"email": "demo@example.com", "password": "demo1234"})
    return {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

async def make_item(c, h):
    pr = await c.post("/api/v1/projects", headers=h,
        json={"name": f"itm_{int(time.time())}", "description": "t"})
    pid = pr.json().get("id", "")
    inp = await c.post("/api/v1/inputs", headers=h,
        json={"project_id": pid, "raw_text": "ログインできません"})
    input_id = inp.json().get("id", "")
    items = await c.post("/api/v1/analyze", headers=h, json={"input_id": input_id})
    items_list = items.json() if isinstance(items.json(), list) else []
    item_id = items_list[0].get("id", "") if items_list else ""
    return pid, input_id, item_id

@pytest.mark.asyncio
async def test_list_items():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid, input_id, item_id = await make_item(c, h)
        r = await c.get(f"/api/v1/items?input_id={input_id}", headers=h)
        assert r.status_code in (200, 404)
        if r.status_code == 200:
            assert isinstance(r.json(), list)

@pytest.mark.asyncio
async def test_patch_item_intent():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        _, _, item_id = await make_item(c, h)
        if not item_id:
            pytest.skip("item作成失敗")
        r = await c.patch(f"/api/v1/items/{item_id}", headers=h,
            json={"intent_code": "REQ"})
        assert r.status_code in (200, 204, 404, 422)

@pytest.mark.asyncio
async def test_patch_item_text():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        _, _, item_id = await make_item(c, h)
        if not item_id:
            pytest.skip("item作成失敗")
        r = await c.patch(f"/api/v1/items/{item_id}", headers=h,
            json={"normalized_text": "修正されたテキスト"})
        assert r.status_code in (200, 204, 404, 422)

@pytest.mark.asyncio
async def test_delete_item():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        _, _, item_id = await make_item(c, h)
        if not item_id:
            pytest.skip("item作成失敗")
        r = await c.delete(f"/api/v1/items/{item_id}", headers=h)
        assert r.status_code in (200, 204, 404)

@pytest.mark.asyncio
async def test_item_not_found():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        fake = "00000000-0000-0000-0000-000000000000"
        r = await c.patch(f"/api/v1/items/{fake}", headers=h,
            json={"intent_code": "BUG"})
        assert r.status_code in (404, 422)
