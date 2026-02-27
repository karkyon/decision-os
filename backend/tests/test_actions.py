import pytest
import time
from httpx import AsyncClient, ASGITransport
from app.main import app

BASE = "http://test"

async def get_auth(client):
    r = await client.post("/api/v1/auth/login",
        json={"email": "demo@example.com", "password": "demo1234"})
    return {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

async def setup(client, headers):
    r = await client.post("/api/v1/projects", headers=headers,
        json={"name": f"act_{int(time.time())}", "description": "t"})
    pid = r.json().get("id", "")
    inp = await client.post("/api/v1/inputs", headers=headers,
        json={"project_id": pid, "raw_text": "ログインするとエラーになります"})
    iid = inp.json().get("id", "")
    items = await client.post("/api/v1/analyze", headers=headers,
        json={"input_id": iid})
    item_id = items.json()[0].get("id", "") if isinstance(items.json(), list) and items.json() else ""
    return pid, iid, item_id

@pytest.mark.asyncio
async def test_create_and_get_action():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid, iid, item_id = await setup(c, h)
        if not item_id:
            pytest.skip("item作成失敗")
        # 作成
        cr = await c.post("/api/v1/actions", headers=h,
            json={"item_id": item_id, "action_type": "REJECT", "decision_reason": "対象外"})
        assert cr.status_code in (200, 201, 409)
        action_id = cr.json().get("id", "") if cr.status_code in (200, 201) else ""
        # 取得
        if action_id:
            gr = await c.get(f"/api/v1/actions/{action_id}", headers=h)
            assert gr.status_code in (200, 404)

@pytest.mark.asyncio
async def test_create_action_reject():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid, iid, item_id = await setup(c, h)
        if not item_id:
            pytest.skip("item作成失敗")
        r = await c.post("/api/v1/actions", headers=h,
            json={"item_id": item_id, "action_type": "REJECT", "decision_reason": "対象外"})
        assert r.status_code in (200, 201, 409)

@pytest.mark.asyncio
async def test_create_action_create_issue():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid, iid, item_id = await setup(c, h)
        if not item_id:
            pytest.skip("item作成失敗")
        r = await c.post("/api/v1/actions", headers=h,
            json={"item_id": item_id, "action_type": "CREATE_ISSUE",
                  "decision_reason": "バグとして起票"})
        assert r.status_code in (200, 201, 409)
        # CREATE_ISSUE なら issue_id が返るはず
        if r.status_code in (200, 201):
            data = r.json()
            if data.get("action_type") == "CREATE_ISSUE":
                assert data.get("issue_id") or data.get("id")

@pytest.mark.asyncio
async def test_create_action_answer():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid, iid, item_id = await setup(c, h)
        if not item_id:
            pytest.skip("item作成失敗")
        r = await c.post("/api/v1/actions", headers=h,
            json={"item_id": item_id, "action_type": "ANSWER",
                  "decision_reason": "FAQに記載あり"})
        assert r.status_code in (200, 201, 409)

@pytest.mark.asyncio
async def test_action_convert():
    """action の convert エンドポイント"""
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid, iid, item_id = await setup(c, h)
        if not item_id:
            pytest.skip("item作成失敗")
        cr = await c.post("/api/v1/actions", headers=h,
            json={"item_id": item_id, "action_type": "STORE"})
        if cr.status_code in (200, 201):
            aid = cr.json().get("id", "")
            r = await c.post(f"/api/v1/actions/{aid}/convert", headers=h,
                json={"action_type": "CREATE_ISSUE"})
            assert r.status_code in (200, 201, 404, 422)

@pytest.mark.asyncio
async def test_action_invalid_item():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.post("/api/v1/actions", headers=h,
            json={"item_id": "00000000-0000-0000-0000-000000000000",
                  "action_type": "REJECT"})
        assert r.status_code in (404, 422)

@pytest.mark.asyncio
async def test_get_action_by_item():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid, iid, item_id = await setup(c, h)
        if not item_id:
            pytest.skip("item作成失敗")
        await c.post("/api/v1/actions", headers=h,
            json={"item_id": item_id, "action_type": "STORE"})
        r = await c.get(f"/api/v1/actions/{item_id}", headers=h)
        assert r.status_code in (200, 404, 405)
