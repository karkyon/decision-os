"""issues.py カバレッジ補完テスト"""
import pytest
pytestmark = pytest.mark.asyncio


async def test_issues_list_all(client, auth_headers):
    r = await client.get("/api/v1/issues", headers=auth_headers)
    assert r.status_code == 200


async def test_issues_filter_assignee(client, auth_headers):
    r = await client.get("/api/v1/issues?assignee_id=00000000-0000-0000-0000-000000000000", headers=auth_headers)
    assert r.status_code == 200


async def test_issues_filter_label(client, auth_headers):
    r = await client.get("/api/v1/issues?label=bug", headers=auth_headers)
    assert r.status_code == 200


async def test_issues_filter_date(client, auth_headers):
    r = await client.get("/api/v1/issues?date_from=2026-01-01&date_to=2026-12-31", headers=auth_headers)
    assert r.status_code == 200


async def test_issues_filter_intent(client, auth_headers):
    r = await client.get("/api/v1/issues?intent_code=BUG,REQ", headers=auth_headers)
    assert r.status_code == 200


async def test_issues_search_q(client, auth_headers):
    r = await client.get("/api/v1/issues?q=test", headers=auth_headers)
    assert r.status_code == 200


async def test_issues_sort_priority(client, auth_headers):
    r = await client.get("/api/v1/issues?sort=priority_desc", headers=auth_headers)
    assert r.status_code == 200


async def test_issues_sort_due_date(client, auth_headers):
    r = await client.get("/api/v1/issues?sort=due_date_asc", headers=auth_headers)
    assert r.status_code == 200


async def test_issues_sort_created_asc(client, auth_headers):
    r = await client.get("/api/v1/issues?sort=created_at_asc", headers=auth_headers)
    assert r.status_code == 200


async def test_issues_get_not_found(client, auth_headers):
    r = await client.get("/api/v1/issues/00000000-0000-0000-0000-000000000000", headers=auth_headers)
    assert r.status_code in (404, 422)
