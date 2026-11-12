import os
from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from app.config import settings
from app.routers import health, auth, admin, ai_agent, courses, sessions, roster, reports, checkin_stub, data_pipeline

app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
    docs_url=f"{settings.API_V1_STR}/docs",
    redoc_url=f"{settings.API_V1_STR}/redoc",
)

# CORS Middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Routers
app.include_router(health.router, prefix=settings.API_V1_STR)
app.include_router(auth.router, prefix=settings.API_V1_STR)
app.include_router(admin.router, prefix=settings.API_V1_STR)
app.include_router(ai_agent.router, prefix=settings.API_V1_STR)
app.include_router(courses.router, prefix=settings.API_V1_STR)
app.include_router(sessions.router, prefix=settings.API_V1_STR)
app.include_router(roster.router, prefix=settings.API_V1_STR)
app.include_router(reports.router, prefix=settings.API_V1_STR)
app.include_router(checkin_stub.router, prefix=settings.API_V1_STR)
app.include_router(data_pipeline.router, prefix=settings.API_V1_STR)

# Mount interactive mobile simulator
preview_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "mock_preview"))
if os.path.exists(preview_path):
    app.mount("/app", StaticFiles(directory=preview_path, html=True), name="app")

# Direct APK binary download route
apk_path = os.path.abspath(
    os.path.join(
        os.path.dirname(__file__),
        "..",
        "..",
        "build",
        "app",
        "outputs",
        "flutter-apk",
        "app-prod-debug.apk",
    )
)


@app.get("/download/app.apk")
async def download_apk():
    if os.path.exists(apk_path):
        return FileResponse(
            path=apk_path,
            filename="AmritaAttendance-prod-debug.apk",
            media_type="application/vnd.android.package-archive",
        )
    return {"error": "APK not found. Please compile the app first."}


@app.get("/")
async def root():
    return {
        "title": settings.PROJECT_NAME,
        "version": settings.VERSION,
        "status": "healthy",
        "apk_download": "/download/app.apk",
        "mobile_simulator": "/app/",
        "api_docs": f"{settings.API_V1_STR}/docs",
        "health": f"{settings.API_V1_STR}/health",
    }
