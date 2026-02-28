"""actions API テスト（async版・実態合わせ）"""
import pytest
pytestmark = pytest.mark.asyncio

async def test_actions_get_not_found(client, auth_headers):
    r = await client.get("/api/v1/actions/00000000-0000-0000-0000-000000000000", headers=auth_headers)
    assert r.status_code in (404, 422)

async def test_actions_convert_not_found(client, auth_headers):
    r = await client.post("/api/v1/actions/00000000-0000-0000-0000-000000000000/convert", headers=auth_headers)
    assert r.status_code in (404, 422)

async def test_actions_create_invalid(client, auth_headers):
    r = await client.post("/api/v1/actions", json={"action_type": "CREATE_ISSUE"}, headers=auth_headers)
    assert r.status_code in (404, 422)

async def test_actions_create_item_not_found(client, auth_headers):
    r = await client.post("/api/v1/actions", json={
        "item_id": "00000000-0000-0000-0000-000000000000",
        "action_type": "CREATE_ISSUE"
    }, headers=auth_headers)
    assert r.status_code in (404, 422)
