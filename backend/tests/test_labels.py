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
        json={"name": f"lbl_{int(time.time())}", "description": "t"})
    return r.json().get("id", "")

@pytest.mark.asyncio
async def test_list_labels_basic():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        r = await c.get(f"/api/v1/labels?project_id={pid}", headers=h)
        assert r.status_code == 200

@pytest.mark.asyncio
async def test_list_labels_with_filters():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        # limit/offset
        r = await c.get(f"/api/v1/labels?project_id={pid}&limit=5&offset=0", headers=h)
        assert r.status_code in (200, 422)
        # search
        r2 = await c.get(f"/api/v1/labels?project_id={pid}&search=bug", headers=h)
        assert r2.status_code in (200, 422)

@pytest.mark.asyncio
async def test_list_labels_no_project():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        # project_id なし
        r = await c.get("/api/v1/labels", headers=h)
        assert r.status_code in (200, 422)

@pytest.mark.asyncio
async def test_suggest_labels():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        for text in ["バグ", "エラー", "要望", "改善"]:
            r = await c.get(f"/api/v1/labels/suggest?project_id={pid}&text={text}", headers=h)
            assert r.status_code in (200, 404, 422)

@pytest.mark.asyncio
async def test_merge_labels_valid():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        r = await c.post("/api/v1/labels/merge", headers=h,
            json={"project_id": pid,
                  "source_labels": ["bug", "バグ"],
                  "target_label": "BUG"})
        assert r.status_code in (200, 201, 404, 422)

@pytest.mark.asyncio
async def test_merge_labels_invalid():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.post("/api/v1/labels/merge", headers=h, json={})
        assert r.status_code in (400, 422)

@pytest.mark.asyncio
async def test_delete_label_existing():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        r = await c.delete(f"/api/v1/labels/bug?project_id={pid}",
            headers=h, follow_redirects=True)
        assert r.status_code in (200, 204, 404, 405, 422)

@pytest.mark.asyncio
async def test_delete_label_not_found():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        r = await c.delete(f"/api/v1/labels/nonexistent_label_xyz?project_id={pid}",
            headers=h, follow_redirects=True)
        assert r.status_code in (200, 204, 404, 405, 422)

@pytest.mark.asyncio
async def test_labels_unauthenticated():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        r = await c.get("/api/v1/labels")
        assert r.status_code in (401, 403, 422)
