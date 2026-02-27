import pytest, time

@pytest.mark.asyncio
async def test_list_projects(client, auth_headers):
    resp = await client.get("/api/v1/projects", headers=auth_headers)
    assert resp.status_code == 200

@pytest.mark.asyncio
async def test_create_project(client, auth_headers):
    resp = await client.post("/api/v1/projects",
        headers=auth_headers,
        json={"name": f"test_{int(time.time())}", "description": "pytest"})
    assert resp.status_code in (200, 201)
    assert "id" in resp.json()
