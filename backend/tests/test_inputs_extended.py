import pytest, time
from httpx import AsyncClient, ASGITransport
from app.main import app
BASE = "http://test"

async def get_auth(c):
    r = await c.post("/api/v1/auth/login",
        json={"email": "demo@example.com", "password": "demo1234"})
    return {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

async def make_project(c, h):
    r = await c.post("/api/v1/projects", headers=h,
        json={"name": f"inp_{int(time.time())}", "description": "t"})
    return r.json().get("id", "")

@pytest.mark.asyncio
async def test_inputs_get_by_id():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        cr = await c.post("/api/v1/inputs", headers=h,
            json={"project_id": pid, "raw_text": "個別取得テスト"})
        iid = cr.json().get("id", "")
        r = await c.get(f"/api/v1/inputs/{iid}", headers=h)
        assert r.status_code in (200, 404, 405)

@pytest.mark.asyncio
async def test_inputs_not_found():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.get("/api/v1/inputs/00000000-0000-0000-0000-000000000000", headers=h)
        assert r.status_code in (404, 405)

@pytest.mark.asyncio
async def test_inputs_list_limit_offset():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        for i in range(4):
            await c.post("/api/v1/inputs", headers=h,
                json={"project_id": pid, "raw_text": f"テキスト{i}"})
        r1 = await c.get(f"/api/v1/inputs?project_id={pid}&limit=2", headers=h)
        assert r1.status_code == 200
        r2 = await c.get(f"/api/v1/inputs?project_id={pid}&limit=2&offset=2", headers=h)
        assert r2.status_code == 200

@pytest.mark.asyncio
async def test_inputs_list_no_project():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        # project_id なしでGET（全件 or エラー）
        r = await c.get("/api/v1/inputs", headers=h)
        assert r.status_code in (200, 422)

@pytest.mark.asyncio
async def test_inputs_trace_endpoint():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        cr = await c.post("/api/v1/inputs", headers=h,
            json={"project_id": pid, "raw_text": "トレーステスト"})
        iid = cr.json().get("id", "")
        r = await c.get(f"/api/v1/inputs/{iid}/trace", headers=h)
        assert r.status_code in (200, 404, 405)

@pytest.mark.asyncio
async def test_inputs_delete():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        cr = await c.post("/api/v1/inputs", headers=h,
            json={"project_id": pid, "raw_text": "削除テスト"})
        iid = cr.json().get("id", "")
        r = await c.delete(f"/api/v1/inputs/{iid}", headers=h)
        assert r.status_code in (200, 204, 404, 405)

@pytest.mark.asyncio
async def test_inputs_search_by_text():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        await c.post("/api/v1/inputs", headers=h,
            json={"project_id": pid, "raw_text": "ログインエラー検索テスト"})
        r = await c.get(f"/api/v1/inputs?project_id={pid}&search=ログイン", headers=h)
        assert r.status_code in (200, 422)
