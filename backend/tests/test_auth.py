import pytest

@pytest.mark.asyncio
async def test_login_success(client):
    resp = await client.post("/api/v1/auth/login", json={
        "email": "demo@example.com", "password": "demo1234"
    })
    assert resp.status_code == 200
    assert "access_token" in resp.json()

@pytest.mark.asyncio
async def test_login_wrong_password(client):
    resp = await client.post("/api/v1/auth/login", json={
        "email": "demo@example.com", "password": "wrong"
    })
    assert resp.status_code in (401, 400, 422)

@pytest.mark.asyncio
async def test_no_token_rejected(client):
    resp = await client.get("/api/v1/projects")
    assert resp.status_code in (401, 403)
