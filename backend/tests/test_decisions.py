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
    r = await client.post("/api/v1/projects",
        headers=headers, json={"name": f"dec_test_{int(time.time())}", "description": "t"})
    return r.json().get("id", "")

@pytest.mark.asyncio
async def test_create_decision():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        r = await c.post("/api/v1/decisions", headers=h,
            json={"project_id": pid, "decision_text": "A案を採用", "reason": "コスト優先"})
        assert r.status_code in (200, 201)
        assert r.json().get("id")

@pytest.mark.asyncio
async def test_list_decisions():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        await c.post("/api/v1/decisions", headers=h,
            json={"project_id": pid, "decision_text": "B案採用", "reason": "速度優先"})
        r = await c.get(f"/api/v1/decisions?project_id={pid}", headers=h)
        assert r.status_code == 200
        assert isinstance(r.json(), list)

@pytest.mark.asyncio
async def test_decision_empty_text():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        h = await get_auth(c)
        pid = await make_project(c, h)
        r = await c.post("/api/v1/decisions", headers=h,
            json={"project_id": pid, "decision_text": "  ", "reason": "理由"})
        assert r.status_code == 422
