import pytest
import time
from httpx import AsyncClient, ASGITransport
from app.main import app

BASE = "http://test"

async def get_auth(client):
    r = await client.post("/api/v1/auth/login",
        json={"email": "demo@example.com", "password": "demo1234"})
    return {"Authorization": f"Bearer {r.json().get('access_token', '')}"}

async def make_project(client, headers):
    r = await client.post("/api/v1/projects", headers=headers,
        json={"name": f"cv_{int(time.time())}", "description": "t"})
    return r.json().get("id", "")

async def make_issue(client, headers, pid):
    r = await client.post("/api/v1/issues", headers=headers,
        json={"project_id": pid, "title": "cv issue", "issue_type": "task", "status": "open"})
    return r.json().get("id", "")

@pytest.mark.asyncio
async def test_create_conversation():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        iid = await make_issue(c, h, pid)
        r = await c.post("/api/v1/conversations", headers=h,
            json={"issue_id": iid, "body": "テストコメント"})
        assert r.status_code in (200, 201)
        assert r.json().get("id")

@pytest.mark.asyncio
async def test_list_conversations():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        iid = await make_issue(c, h, pid)
        await c.post("/api/v1/conversations", headers=h,
            json={"issue_id": iid, "body": "コメント1"})
        r = await c.get(f"/api/v1/conversations?issue_id={iid}", headers=h)
        assert r.status_code == 200
        assert len(r.json()) >= 1

@pytest.mark.asyncio
async def test_update_conversation():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        iid = await make_issue(c, h, pid)
        cr = await c.post("/api/v1/conversations", headers=h,
            json={"issue_id": iid, "body": "元のコメント"})
        cid = cr.json().get("id", "")
        r = await c.patch(f"/api/v1/conversations/{cid}", headers=h,
            json={"body": "編集後のコメント"})
        assert r.status_code in (200, 201)
        assert r.json().get("body") == "編集後のコメント"

@pytest.mark.asyncio
async def test_delete_conversation():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        iid = await make_issue(c, h, pid)
        cr = await c.post("/api/v1/conversations", headers=h,
            json={"issue_id": iid, "body": "削除するコメント"})
        cid = cr.json().get("id", "")
        r = await c.delete(f"/api/v1/conversations/{cid}", headers=h)
        assert r.status_code in (200, 204)

@pytest.mark.asyncio
async def test_conversation_empty_body():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        iid = await make_issue(c, h, pid)
        r = await c.post("/api/v1/conversations", headers=h,
            json={"issue_id": iid, "body": "   "})
        assert r.status_code == 422

@pytest.mark.asyncio
async def test_conversation_invalid_issue():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        r = await c.post("/api/v1/conversations", headers=h,
            json={"issue_id": "00000000-0000-0000-0000-000000000000", "body": "test"})
        assert r.status_code == 404
