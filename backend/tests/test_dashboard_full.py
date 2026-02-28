"""dashboard API テスト（async版）"""
import pytest

pytestmark = pytest.mark.asyncio


async def test_dashboard_counts_ok(client, auth_headers):
    """GET /dashboard/counts → 200 + 構造確認"""
    r = await client.get("/api/v1/dashboard/counts", headers=auth_headers)
    assert r.status_code == 200
    data = r.json()
    assert "inputs" in data
    assert "items" in data
    assert "issues" in data


async def test_dashboard_counts_structure(client, auth_headers):
    """レスポンス構造の詳細確認"""
    r = await client.get("/api/v1/dashboard/counts", headers=auth_headers)
    assert r.status_code == 200
    data = r.json()
    issues = data.get("issues", {})
    if "recent" in issues:
        assert isinstance(issues["recent"], list)


async def test_dashboard_counts_with_project(client, auth_headers):
    """project_id フィルタ付き"""
    r = await client.get("/api/v1/dashboard/counts?project_id=00000000-0000-0000-0000-000000000000",
                         headers=auth_headers)
    assert r.status_code in (200, 404)


async def test_dashboard_unauthorized(client):
    """未認証 → 401/403"""
    r = await client.get("/api/v1/dashboard/counts")
    assert r.status_code in (401, 403, 422)
