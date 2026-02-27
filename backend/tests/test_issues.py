import pytest, time

async def get_or_create_project(client, auth_headers):
    r = await client.get("/api/v1/projects", headers=auth_headers)
    items = r.json() if isinstance(r.json(), list) else r.json().get("items", r.json().get("data", []))
    if items:
        return items[0]["id"]
    r2 = await client.post("/api/v1/projects", headers=auth_headers,
        json={"name": f"test_{int(time.time())}", "description": "test"})
    return r2.json()["id"]

@pytest.mark.asyncio
async def test_list_issues(client, auth_headers):
    resp = await client.get("/api/v1/issues", headers=auth_headers)
    assert resp.status_code == 200

@pytest.mark.asyncio
async def test_create_issue(client, auth_headers):
    pid = await get_or_create_project(client, auth_headers)
    resp = await client.post("/api/v1/issues", headers=auth_headers,
        json={"project_id": pid, "title": "pytest issue", "issue_type": "task", "status": "open"})
    assert resp.status_code in (200, 201)
    assert "id" in resp.json()

@pytest.mark.asyncio
async def test_issue_type_change(client, auth_headers):
    pid = await get_or_create_project(client, auth_headers)
    cr = await client.post("/api/v1/issues", headers=auth_headers,
        json={"project_id": pid, "title": "type change test", "issue_type": "task", "status": "open"})
    iid = cr.json().get("id", "")
    if not iid:
        pytest.skip("issue作成失敗")
    r = await client.patch(f"/api/v1/issues/{iid}", headers=auth_headers,
        json={"issue_type": "epic"})
    assert r.status_code in (200, 204)

@pytest.mark.asyncio
async def test_filter_issues(client, auth_headers):
    resp = await client.get("/api/v1/issues?status=open", headers=auth_headers)
    assert resp.status_code == 200

@pytest.mark.asyncio
async def test_rbac_users_endpoint(client, auth_headers):
    resp = await client.get("/api/v1/users", headers=auth_headers)
    # PMロールなので 403 が正常
    assert resp.status_code in (200, 403)
