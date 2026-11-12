from typing import Optional, Dict, Any
from pydantic import BaseModel
from fastapi import APIRouter, Depends
from app.auth.rbac import AuthenticatedUser, get_current_user
from app.ai.agent_client import ai_agent_client

router = APIRouter(prefix="/ai", tags=["AI Attendance Agent"])


class AIQueryRequest(BaseModel):
    prompt: str
    attended_classes: Optional[int] = None
    total_classes: Optional[int] = None


class AIQueryResponse(BaseModel):
    query: str
    response: str
    source: str
    model: str
    bucket: str
    calculation: Optional[Dict[str, Any]] = None


@router.post("/query", response_model=AIQueryResponse)
async def query_ai_agent(
    payload: AIQueryRequest,
    current_user: AuthenticatedUser = Depends(get_current_user),
):
    """
    Submits an attendance policy query or grievance calculation to the AI Agent.
    Connects with Hugging Face model priyanrajj/attendanceagent and bucket priyanrajj/attendanceagent-bucket.
    """
    context = {}
    if payload.attended_classes is not None and payload.total_classes is not None:
        context["attended"] = payload.attended_classes
        context["total"] = payload.total_classes

    result = await ai_agent_client.query(
        prompt=payload.prompt,
        user_role=current_user.role,
        context=context if context else None,
    )

    return AIQueryResponse(
        query=result["query"],
        response=result["response"],
        source=result["source"],
        model=result["model"],
        bucket=result["bucket"],
        calculation=result.get("calculation"),
    )
