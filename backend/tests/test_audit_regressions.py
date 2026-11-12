import pytest
from httpx import AsyncClient
from app.main import app
from app.auth.rbac import get_current_user, AuthenticatedUser
from app.ai.agent_client import AttendancePolicyEngine


def test_amrita_policy_engine_calculations():
    """
    Verifies policy calculation oracle for 75% Amrita minimum attendance.
    """
    # Case 1: 18 out of 20 = 90% (Safe)
    calc1 = AttendancePolicyEngine.calculate_margin(18, 20)
    assert calc1["percentage"] == 90.0
    assert calc1["status"] == "Safe"
    assert calc1["safe_skips"] >= 1

    # Case 2: 14 out of 20 = 70% (Shortage - Condonable)
    calc2 = AttendancePolicyEngine.calculate_margin(14, 20)
    assert calc2["percentage"] == 70.0
    assert "Condonation Eligible" in calc2["status"]
    assert calc2["classes_needed"] > 0

    # Case 3: 10 out of 20 = 50% (Critical Shortage - FA Risk)
    calc3 = AttendancePolicyEngine.calculate_margin(10, 20)
    assert calc3["percentage"] == 50.0
    assert "FA Risk" in calc3["status"]


@pytest.mark.asyncio
async def test_proximity_checkin_returns_501_stub(client: AsyncClient):
    """
    Regression: Proximity check-in must return 501 Not Implemented pending BLE calibration.
    """
    payload = {
        "session_id": "00000000-0000-0000-0000-000000000001",
        "ephemeral_nonce": "abcdef0123456789",
        "observed_rssi": -65,
    }
    res = await client.post("/api/v1/attendance/check-in", json=payload)
    assert res.status_code == 501
    assert "Proximity check-in is pending BLE field calibration" in res.json()["detail"]


@pytest.mark.asyncio
async def test_ai_agent_query_endpoint(
    client: AsyncClient, mock_student_user: AuthenticatedUser
):
    """
    Verifies AI query endpoint with Hugging Face model/bucket metadata.
    """
    app.dependency_overrides[get_current_user] = lambda: mock_student_user

    res = await client.post(
        "/api/v1/ai/query",
        json={
            "prompt": "What is the minimum attendance required for semester exams?",
            "attended_classes": 14,
            "total_classes": 20,
        },
    )
    assert res.status_code == 200
    data = res.json()
    assert "75%" in data["response"]
    assert data["model"] == "priyanrajj/attendanceagent"
    assert data["bucket"] == "priyanrajj/attendanceagent-bucket"
    assert data["calculation"] is not None
    assert data["calculation"]["percentage"] == 70.0

    app.dependency_overrides.clear()
