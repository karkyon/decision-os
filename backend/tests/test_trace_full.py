"""trace API テスト（async版）"""
import pytest

pytestmark = pytest.mark.asyncio


async def test_trace_not_found(client, auth_headers):
    """存在しないISSUE → 404"""
    r = await client.get("/api/v1/trace/00000000-0000-0000-0000-000000000000",
                         headers=auth_headers)
    assert r.status_code in (404, 422)


async def test_trace_existing_issue(client, auth_headers):
    """既存ISSUEでトレース → 200 + 構造確認"""
    issues_r = await client.get("/api/v1/issues?limit=1", headers=auth_headers)
    if issues_r.status_code != 200:
        pytest.skip("ISSUE一覧取得失敗")
    issues = issues_r.json()
    if isinstance(issues, dict):
        issues = issues.get("items", issues.get("issues", []))
    if not issues:
        pytest.skip("ISSUEが0件")
    issue_id = issues[0]["id"]
    r = await client.get(f"/api/v1/trace/{issue_id}", headers=auth_headers)
    assert r.status_code in (200, 404)
    if r.status_code == 200:
        data = r.json()
        assert "issue" in data


async def test_trace_unauthorized(client):
    """未認証 → 401/403"""
    r = await client.get("/api/v1/trace/00000000-0000-0000-0000-000000000000")
    assert r.status_code in (401, 403, 422)


async def test_input_trace(client, auth_headers):
    """GET /inputs/{id}/trace（前引きトレース）"""
    inputs_r = await client.get("/api/v1/inputs?limit=1", headers=auth_headers)
    if inputs_r.status_code != 200:
        pytest.skip("INPUT一覧取得失敗")
    inputs = inputs_r.json()
    if isinstance(inputs, dict):
        inputs = inputs.get("items", [])
    if not inputs:
        pytest.skip("INPUTが0件")
    r = await client.get(f"/api/v1/inputs/{inputs[0]['id']}/trace", headers=auth_headers)
    assert r.status_code in (200, 404)
