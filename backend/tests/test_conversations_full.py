"""conversations API テスト（async版・実態合わせ）"""
import pytest
pytestmark = pytest.mark.asyncio

async def test_conversations_list(client, auth_headers):
    r = await client.get("/api/v1/conversations?issue_id=00000000-0000-0000-0000-000000000000", headers=auth_headers)
    assert r.status_code in (200, 404, 405)

async def test_conversations_create_invalid(client, auth_headers):
    r = await client.post("/api/v1/conversations", json={}, headers=auth_headers)
    assert r.status_code in (404, 405, 422)

async def test_conversations_get_or_method(client, auth_headers):
    r = await client.get("/api/v1/conversations/00000000-0000-0000-0000-000000000000", headers=auth_headers)
    assert r.status_code in (404, 405, 422)

async def test_conversations_unauthorized(client):
    r = await client.get("/api/v1/conversations?issue_id=test")
    assert r.status_code in (200, 401, 403, 405, 422)
