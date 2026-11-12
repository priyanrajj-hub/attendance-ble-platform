import time
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text
from app.db.session import get_db

router = APIRouter(prefix="/health", tags=["Health"])


@router.get("", status_code=status.HTTP_200_OK)
async def health_check(db: AsyncSession = Depends(get_db)):
    """
    Authoritative service health probe.
    Executes a live `SELECT 1` query against the PostgreSQL database.
    """
    start_time = time.perf_counter()
    try:
        result = await db.execute(text("SELECT 1"))
        scalar_val = result.scalar()
        latency_ms = round((time.perf_counter() - start_time) * 1000, 2)
        
        if scalar_val != 1:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Database health probe returned unexpected result.",
            )
            
        return {
            "status": "healthy",
            "database": "connected",
            "database_latency_ms": latency_ms,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Database connection failure: {str(e)}",
        )
