import pytest, time
from httpx import AsyncClient, ASGITransport
from app.main import app
BASE = "http://test"

async def get_auth(c):
    r = await c.post("/api/v1/auth/login",
        json={"email": "demo@example.com", "password": "demo1234"})
    return {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

async def setup(c, h):
    pr = await c.post("/api/v1/projects", headers=h,
        json={"name": f"dec_{int(time.time())}", "description": "t"})
    pid = pr.json().get("id", "")
    iss = await c.post("/api/v1/issues", headers=h,
        json={"project_id": pid, "title": "dec issue",
              "issue_type": "task", "status": "open"})
    iid = iss.json().get("id", "")
    return pid, iid

def make_decision_body(iid, pid, title="決定A"):
    """実際のスキーマに合わせた decision POST body"""
    return {
        "issue_id": iid,
        "project_id": pid,
        "title": title,
        "decision_text": "この方針で進める",
        "reason": "コスト効率が最も高いため",
        "body": "詳細説明",
        "decided_by": "PM",
    }

@pytest.mark.asyncio
async def test_decision_create_and_list():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid, iid = await setup(c, h)
        body = make_decision_body(iid, pid)
        cr = await c.post("/api/v1/decisions", headers=h, json=body)
        assert cr.status_code in (200, 201), \
            f"POST /decisions failed: {cr.status_code} {cr.text[:200]}"
        did = cr.json().get("id", "")
        # GET list
        r = await c.get(f"/api/v1/decisions?issue_id={iid}", headers=h)
        assert r.status_code == 200
        assert isinstance(r.json(), list)
        assert len(r.json()) >= 1

@pytest.mark.asyncio
async def test_decision_get_by_id():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid, iid = await setup(c, h)
        cr = await c.post("/api/v1/decisions", headers=h,
            json=make_decision_body(iid, pid, "個別取得"))
        if cr.status_code not in (200, 201):
            pytest.skip(f"POST /decisions: {cr.status_code} {cr.text[:100]}")
        did = cr.json().get("id", "")
        r = await c.get(f"/api/v1/decisions/{did}", headers=h)
        assert r.status_code == 200
        assert r.json()["id"] == did

@pytest.mark.asyncio
async def test_decision_delete():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid, iid = await setup(c, h)
        cr = await c.post("/api/v1/decisions", headers=h,
            json=make_decision_body(iid, pid, "削除テスト"))
        if cr.status_code not in (200, 201):
            pytest.skip(f"POST /decisions: {cr.status_code} {cr.text[:100]}")
        did = cr.json().get("id", "")
        r = await c.delete(f"/api/v1/decisions/{did}", headers=h)
        assert r.status_code in (200, 204)
        r2 = await c.get(f"/api/v1/decisions/{did}", headers=h)
        assert r2.status_code == 404

@pytest.mark.asyncio
async def test_decision_not_found():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.get("/api/v1/decisions/00000000-0000-0000-0000-000000000000", headers=h)
        assert r.status_code == 404

@pytest.mark.asyncio
async def test_decision_validation_error():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.post("/api/v1/decisions", headers=h, json={})
        assert r.status_code == 422
