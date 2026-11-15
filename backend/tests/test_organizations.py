import pytest

@pytest.mark.asyncio
async def test_create_organization_as_sys_admin(async_client):
    """Test successful creation of an organization by a system admin."""
    # 1. Register a system admin user
    admin_payload = {
        "email": "sysadmin.org@spacemedx.org",
        "password": "SecurePassword123!",
        "full_name": "System Admin",
        "role": "sys_admin"
    }
    await async_client.post("/api/v1/auth/register", json=admin_payload)
    
    login_res = await async_client.post(
        "/api/v1/auth/login",
        json={"email": admin_payload["email"], "password": admin_payload["password"]}
    )
    assert login_res.status_code == 200
    token = login_res.json()["access_token"]

    # 2. Create organization
    org_payload = {
        "name": "National Aeronautics and Space Administration",
        "code": "NASA",
        "description": "Civil space program and aeronautics research."
    }
    response = await async_client.post(
        "/api/v1/organizations",
        json=org_payload,
        headers={"Authorization": f"Bearer {token}"}
    )
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == org_payload["name"]
    assert data["code"] == "NASA"
    assert data["status"] == "active"
    assert "id" in data


@pytest.mark.asyncio
async def test_create_organization_forbidden_for_astronaut(async_client):
    """Test that regular astronauts cannot create organizations (returns 403 Forbidden)."""
    astro_payload = {
        "email": "astronaut.org@spacemedx.org",
        "password": "SecurePassword123!",
        "full_name": "Astro Sam",
        "role": "astronaut"
    }
    await async_client.post("/api/v1/auth/register", json=astro_payload)
    
    login_res = await async_client.post(
        "/api/v1/auth/login",
        json={"email": astro_payload["email"], "password": astro_payload["password"]}
    )
    assert login_res.status_code == 200
    token = login_res.json()["access_token"]

    response = await async_client.post(
        "/api/v1/organizations",
        json={"name": "Forbidden Org", "code": "FORBIDDEN"},
        headers={"Authorization": f"Bearer {token}"}
    )
    assert response.status_code == 403


@pytest.mark.asyncio
async def test_add_organization_member(async_client):
    """Test assigning a user as a researcher to an organization."""
    # 1. Register admin
    admin_payload = {
        "email": "admin.member@spacemedx.org",
        "password": "SecurePassword123!",
        "full_name": "Org Admin",
        "role": "org_admin"
    }
    await async_client.post("/api/v1/auth/register", json=admin_payload)
    admin_login = await async_client.post(
        "/api/v1/auth/login",
        json={"email": admin_payload["email"], "password": admin_payload["password"]}
    )
    token = admin_login.json()["access_token"]

    # 2. Register researcher user to be added
    researcher_payload = {
        "email": "researcher.member@spacemedx.org",
        "password": "SecurePassword123!",
        "full_name": "Dr. Researcher",
        "role": "researcher"
    }
    reg_res = await async_client.post("/api/v1/auth/register", json=researcher_payload)
    assert reg_res.status_code == 201
    researcher_id = reg_res.json()["id"]

    # 3. Create an organization
    org_res = await async_client.post(
        "/api/v1/organizations",
        json={"name": "European Space Agency", "code": "ESA"},
        headers={"Authorization": f"Bearer {token}"}
    )
    assert org_res.status_code == 201
    org_id = org_res.json()["id"]

    # 4. Add member to organization
    membership_res = await async_client.post(
        f"/api/v1/organizations/{org_id}/members",
        json={"user_id": researcher_id, "role_in_org": "researcher"},
        headers={"Authorization": f"Bearer {token}"}
    )
    assert membership_res.status_code == 201
    mem_data = membership_res.json()
    assert mem_data["user_id"] == researcher_id
    assert mem_data["organization_id"] == org_id
    assert mem_data["role_in_org"] == "researcher"