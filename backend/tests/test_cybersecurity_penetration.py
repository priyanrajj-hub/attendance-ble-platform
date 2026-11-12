import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_security_headers_present(client: AsyncClient):
    """
    Penetration Test: Ensure OWASP enterprise security headers are enforced on all responses.
    """
    res = await client.get("/")
    assert res.status_code == 200

    headers = res.headers
    assert headers.get("X-Frame-Options") == "SAMEORIGIN"
    assert headers.get("X-Content-Type-Options") == "nosniff"
    assert headers.get("X-XSS-Protection") == "1; mode=block"
    assert "max-age=" in headers.get("Strict-Transport-Security", "")
    assert headers.get("Referrer-Policy") == "strict-origin-when-cross-origin"
    assert "camera=()" in headers.get("Permissions-Policy", "")


@pytest.mark.asyncio
async def test_api_cache_control_headers(client: AsyncClient):
    """
    Penetration Test: Ensure sensitive API routes enforce no-store/no-cache
    to prevent intermediate proxies and browsers from caching student PII.
    """
    res = await client.get("/api/v1/health")
    assert res.status_code == 200
    assert "no-store" in res.headers.get("Cache-Control", "")
    assert res.headers.get("Pragma") == "no-cache"


@pytest.mark.asyncio
async def test_path_traversal_attack_blocked(client: AsyncClient):
    """
    Penetration Test: Attempt directory traversal attacks via relative path segments
    and encoded dots.
    """
    attack_uris = [
        "/api/v1/health?file=../../../../etc/passwd",
        "/api/v1/health?target=%2e%2e%2f%2e%2e%2fetc%2fpasswd",
        "/api/v1/health?path=..\\..\\Windows\\System32\\cmd.exe",
    ]
    for uri in attack_uris:
        res = await client.get(uri)
        assert res.status_code == 400
        assert "Path traversal" in res.json().get("detail", "")


@pytest.mark.asyncio
async def test_sql_injection_resilience(client: AsyncClient):
    """
    Penetration Test: Fuzz query parameters with SQL injection payloads
    to verify ORM parameter binding prevents syntax errors or data exfiltration.
    """
    sqli_payloads = [
        "' OR '1'='1",
        "'; DROP TABLE users; --",
        "1 UNION SELECT null, null, null--",
        "admin'--",
    ]
    for payload in sqli_payloads:
        # Fuzz compliance matrix query parameter
        res = await client.get(f"/api/v1/pipeline/compliance-matrix?course_id={payload}")
        # Must return 401 (blocked by auth) or 200 (safe empty set), NEVER 500 Database Error
        assert res.status_code in (401, 200), f"Unexpected status {res.status_code} on payload {payload}"


@pytest.mark.asyncio
async def test_download_hub_landing_page(client: AsyncClient):
    """
    Ensure the APK download hub renders cleanly with embedded QR code.
    """
    res = await client.get("/download")
    assert res.status_code == 200
    assert "text/html" in res.headers.get("content-type", "")
    assert "Amrita BLE Attendance" in res.text
    assert "data:image/png;base64," in res.text
    assert "/download/app.apk" in res.text
