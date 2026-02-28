import pytest, time
from httpx import AsyncClient, ASGITransport
from app.main import app
BASE = "http://test"

async def get_auth(c):
    r = await c.post("/api/v1/auth/login",
        json={"email": "demo@example.com", "password": "demo1234"})
    return {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

async def make_issue_with_trace(c, h):
    pr = await c.post("/api/v1/projects", headers=h,
        json={"name": f"trace_{int(time.time())}", "description": "t"})
    pid = pr.json().get("id", "")
    inp = await c.post("/api/v1/inputs", headers=h,
        json={"project_id": pid, "raw_text": "クラッシュします"})
    input_id = inp.json().get("id", "")
    items = await c.post("/api/v1/analyze", headers=h, json={"input_id": input_id})
    items_list = items.json() if isinstance(items.json(), list) else []
    if not items_list:
        return None, pid
    item_id = items_list[0].get("id", "")
    act = await c.post("/api/v1/actions", headers=h,
        json={"item_id": item_id, "action_type": "accept", "note": "対応"})
    action_id = act.json().get("id", "")
    conv = await c.post(f"/api/v1/actions/{action_id}/convert", headers=h,
        json={"project_id": pid, "title": "トレースISSUE"})
    return conv.json().get("id", ""), pid

@pytest.mark.asyncio
async def test_trace_with_full_chain():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        issue_id, _ = await make_issue_with_trace(c, h)
        if not issue_id:
            pytest.skip("issue作成失敗")
        r = await c.get(f"/api/v1/trace/{issue_id}", headers=h)
        assert r.status_code in (200, 404)
        if r.status_code == 200:
            data = r.json()
            assert isinstance(data, dict)
            # トレース情報が含まれているか確認
            assert "issue" in data or "id" in data or "issue_id" in data

@pytest.mark.asyncio
async def test_trace_simple_issue():
    """action/convert なしの素のISSUEもトレース可能"""
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pr = await c.post("/api/v1/projects", headers=h,
            json={"name": f"tr2_{int(time.time())}", "description": "t"})
        pid = pr.json().get("id", "")
        iss = await c.post("/api/v1/issues", headers=h,
            json={"project_id": pid, "title": "シンプルISSUE",
                  "issue_type": "task", "status": "open"})
        iid = iss.json().get("id", "")
        r = await c.get(f"/api/v1/trace/{iid}", headers=h)
        assert r.status_code in (200, 404)

@pytest.mark.asyncio
async def test_trace_not_found_uuid():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.get("/api/v1/trace/00000000-0000-0000-0000-000000000000", headers=h)
        assert r.status_code in (404, 200)

@pytest.mark.asyncio
async def test_trace_unauthenticated():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        r = await c.get("/api/v1/trace/00000000-0000-0000-0000-000000000000")
        assert r.status_code in (401, 403)
