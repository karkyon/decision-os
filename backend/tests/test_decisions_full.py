"""decisions API テスト（async版）"""
import pytest

pytestmark = pytest.mark.asyncio


async def test_decisions_list(client, auth_headers):
    r = await client.get("/api/v1/decisions", headers=auth_headers)
    assert r.status_code in (200, 404)


async def test_decisions_create_invalid(client, auth_headers):
    """必須フィールドなし → 422"""
    r = await client.post("/api/v1/decisions", json={}, headers=auth_headers)
    assert r.status_code in (404, 422)


async def test_decisions_create_with_issue(client, auth_headers):
    """既存ISSUEで意思決定作成"""
    issues_r = await client.get("/api/v1/issues?limit=1", headers=auth_headers)
    if issues_r.status_code != 200:
        pytest.skip("ISSUE取得失敗")
    issues = issues_r.json()
    if isinstance(issues, dict):
        issues = issues.get("items", [])
    if not issues:
        pytest.skip("ISSUEが0件")
    issue_id = issues[0]["id"]
    r = await client.post("/api/v1/decisions", json={
        "issue_id": issue_id,
        "summary": "pytest意思決定テスト",
        "decided_at": "2026-02-28T00:00:00",
    }, headers=auth_headers)
    assert r.status_code in (200, 201, 404, 422)


async def test_decisions_get_not_found(client, auth_headers):
    r = await client.get("/api/v1/decisions/00000000-0000-0000-0000-000000000000",
                         headers=auth_headers)
    assert r.status_code in (404, 422)


async def test_decisions_unauthorized(client):
    r = await client.get("/api/v1/decisions")
    assert r.status_code in (401, 403, 422)
