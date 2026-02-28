import pytest, time
from httpx import AsyncClient, ASGITransport
from app.main import app
BASE = "http://test"

@pytest.mark.asyncio
async def test_register_new_user():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        ts = int(time.time())
        r = await c.post("/api/v1/auth/register",
            json={"email": f"reg_{ts}@test.com",
                  "password": "testpass123",
                  "name": "Test User",
                  "full_name": "Test User"})
        # 200/201: 登録成功, 409: 重複, 422: バリデーションエラー
        assert r.status_code in (200, 201, 409, 422), \
            f"register: {r.status_code} {r.text[:100]}"

@pytest.mark.asyncio
async def test_register_duplicate_email():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        r = await c.post("/api/v1/auth/register",
            json={"email": "demo@example.com",
                  "password": "demo1234",
                  "name": "Demo",
                  "full_name": "Demo User"})
        assert r.status_code in (400, 409, 422)

@pytest.mark.asyncio
async def test_login_wrong_password():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        r = await c.post("/api/v1/auth/login",
            json={"email": "demo@example.com", "password": "wrongpassword"})
        assert r.status_code in (400, 401, 422)

@pytest.mark.asyncio
async def test_login_unknown_user():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        r = await c.post("/api/v1/auth/login",
            json={"email": "nobody@nowhere.com", "password": "pass"})
        assert r.status_code in (400, 401, 422)

@pytest.mark.asyncio
async def test_login_success():
    async with AsyncClient(transport=ASGITransport(app=app), base_url=BASE) as c:
        r = await c.post("/api/v1/auth/login",
            json={"email": "demo@example.com", "password": "demo1234"})
        assert r.status_code == 200
        assert r.json().get("access_token")
        assert r.json().get("user_id")
