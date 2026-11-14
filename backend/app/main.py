import os
import io
import base64
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
import qrcode

from app.config import settings
from app.auth.security_middleware import (
    EnterpriseSecurityHeadersMiddleware,
    RateLimiterAntiDDoSMiddleware,
    PathTraversalAndInputDefenseMiddleware,
)
from app.routers import (
    health,
    auth,
    admin,
    ai_agent,
    courses,
    sessions,
    roster,
    reports,
    checkin_stub,
    data_pipeline,
)

app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
    docs_url=f"{settings.API_V1_STR}/docs",
    redoc_url=f"{settings.API_V1_STR}/redoc",
)

# 1. Enterprise Cyber-Security & DDoS Protection Middlewares
app.add_middleware(EnterpriseSecurityHeadersMiddleware)
app.add_middleware(PathTraversalAndInputDefenseMiddleware)
app.add_middleware(RateLimiterAntiDDoSMiddleware)

# 2. CORS Middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 3. Mount Microservice Routers
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

# 4. Mount Interactive Web Application & Anime Simulator
preview_path = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "mock_preview")
)
if os.path.exists(preview_path):
    app.mount("/app", StaticFiles(directory=preview_path, html=True), name="app")

# 5. Direct APK Binary Paths
apk_dir = os.path.abspath(
    os.path.join(
        os.path.dirname(__file__),
        "..",
        "..",
        "build",
        "app",
        "outputs",
        "flutter-apk",
    )
)
apk_arm64_path = os.path.join(apk_dir, "app-arm64-v8a-release.apk")
apk_universal_path = os.path.join(apk_dir, "app-release.apk")
apk_arm32_path = os.path.join(apk_dir, "app-armeabi-v7a-release.apk")
apk_debug_path = os.path.join(apk_dir, "app-prod-debug.apk")

# Default primary APK (prefer optimized release arm64, fallback to universal or debug)
if os.path.exists(apk_arm64_path):
    apk_path = apk_arm64_path
    apk_default_name = "AmritaAttendance-arm64-release.apk"
elif os.path.exists(apk_universal_path):
    apk_path = apk_universal_path
    apk_default_name = "AmritaAttendance-universal-release.apk"
else:
    apk_path = apk_debug_path
    apk_default_name = "AmritaAttendance-prod-debug.apk"


@app.api_route("/download/app.apk", methods=["GET", "HEAD"], summary="Download compiled Android APK binary (Default arm64-v8a)")
async def download_apk():
    """Streams the signed production Android APK directly to mobile or desktop browsers."""
    target_path = apk_arm64_path if os.path.exists(apk_arm64_path) else (apk_universal_path if os.path.exists(apk_universal_path) else apk_path)
    if os.path.exists(target_path):
        return FileResponse(
            path=target_path,
            filename=os.path.basename(target_path),
            media_type="application/vnd.android.package-archive",
            headers={
                "Accept-Ranges": "bytes",
                "Content-Disposition": f'attachment; filename="{os.path.basename(target_path)}"',
                "Cache-Control": "public, max-age=3600",
            },
        )
    raise HTTPException(status_code=404, detail="APK not found. Please compile the app first.")


@app.api_route("/download/universal", methods=["GET", "HEAD"], summary="Download Universal Release APK")
async def download_universal_apk():
    if os.path.exists(apk_universal_path):
        return FileResponse(
            path=apk_universal_path,
            filename="AmritaAttendance-universal-release.apk",
            media_type="application/vnd.android.package-archive",
            headers={
                "Accept-Ranges": "bytes",
                "Content-Disposition": 'attachment; filename="AmritaAttendance-universal-release.apk"',
            },
        )
    raise HTTPException(status_code=404, detail="Universal APK not found.")


@app.api_route("/download/arm64", methods=["GET", "HEAD"], summary="Download arm64-v8a Release APK")
async def download_arm64_apk():
    if os.path.exists(apk_arm64_path):
        return FileResponse(
            path=apk_arm64_path,
            filename="AmritaAttendance-arm64-release.apk",
            media_type="application/vnd.android.package-archive",
            headers={
                "Accept-Ranges": "bytes",
                "Content-Disposition": 'attachment; filename="AmritaAttendance-arm64-release.apk"',
            },
        )
    raise HTTPException(status_code=404, detail="ARM64 APK not found.")


@app.get("/download", response_class=HTMLResponse, summary="APK Download Hub with QR Code")
async def download_landing_page():
    """Generates a responsive APK download hub with an auto-generated QR code for instant mobile camera scanning."""
    base_url = os.getenv("PUBLIC_BASE_URL", "http://localhost:8000")
    qr_data = f"{base_url}/download/app.apk"
    qr = qrcode.QRCode(
        version=1,
        box_size=8,
        border=2,
    )
    qr.add_data(qr_data)
    qr.make(fit=True)
    img = qr.make_image(fill_color="#6366f1", back_color="#0b0b14")
    
    buffered = io.BytesIO()
    img.save(buffered, format="PNG")
    qr_b64 = base64.b64encode(buffered.getvalue()).decode()

    html = f"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Download Amrita BLE Attendance App</title>
      <style>
        body {{
          background: #090a16;
          color: #f8fafc;
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
          display: flex;
          align-items: center;
          justify-content: center;
          min-height: 100vh;
          margin: 0;
          padding: 20px;
          box-sizing: border-box;
        }}
        .card {{
          background: rgba(23, 26, 52, 0.85);
          border: 1px solid rgba(129, 140, 248, 0.3);
          border-radius: 24px;
          padding: 32px;
          max-width: 480px;
          width: 100%;
          text-align: center;
          box-shadow: 0 20px 40px rgba(0,0,0,0.5);
        }}
        .badge {{
          background: rgba(16, 185, 129, 0.2);
          color: #10b981;
          padding: 6px 14px;
          border-radius: 20px;
          font-size: 13px;
          font-weight: 600;
          display: inline-block;
          margin-bottom: 16px;
        }}
        h1 {{ font-size: 24px; margin-bottom: 8px; font-weight: 700; }}
        p {{ color: #94a3b8; font-size: 14px; line-height: 1.5; margin-bottom: 20px; }}
        .notice {{
          background: rgba(239, 68, 68, 0.15);
          border: 1px solid rgba(239, 68, 68, 0.4);
          color: #fca5a5;
          padding: 12px;
          border-radius: 12px;
          font-size: 13px;
          margin-bottom: 20px;
          text-align: left;
        }}
        .notice strong {{ color: #ffffff; display: block; margin-bottom: 4px; }}
        .qr-box {{
          background: #0b0b14;
          padding: 16px;
          border-radius: 16px;
          display: inline-block;
          border: 2px solid rgba(99, 102, 241, 0.4);
          margin-bottom: 20px;
        }}
        .qr-box img {{ display: block; border-radius: 8px; max-width: 180px; height: auto; }}
        .btn {{
          display: block;
          width: 100%;
          background: linear-gradient(135deg, #6366f1, #4f46e5);
          color: white;
          text-decoration: none;
          padding: 14px;
          border-radius: 14px;
          font-weight: 600;
          font-size: 15px;
          box-sizing: border-box;
          transition: transform 0.2s;
          margin-bottom: 10px;
        }}
        .btn:hover {{ transform: translateY(-2px); }}
        .btn-sec {{
          display: block;
          width: 100%;
          background: rgba(255, 255, 255, 0.08);
          color: #c7d2fe;
          text-decoration: none;
          padding: 10px;
          border-radius: 12px;
          font-weight: 500;
          font-size: 13px;
          box-sizing: border-box;
          margin-bottom: 8px;
        }}
        .instructions {{
          margin-top: 20px;
          text-align: left;
          background: rgba(15, 23, 42, 0.6);
          padding: 14px;
          border-radius: 12px;
          font-size: 12px;
          color: #cbd5e1;
          line-height: 1.6;
        }}
      </style>
    </head>
    <body>
      <div class="card">
        <div class="badge">✓ Production Release Build v1.0.0+1</div>
        <h1>Amrita BLE Attendance</h1>
        <p>Real BLE Attendance Platform for Faculty & Students</p>
        
        <div class="notice">
          <strong>⚠️ Wi-Fi Network Requirement:</strong>
          Your phone MUST be connected to the <strong>same Wi-Fi network</strong> as this PC (192.168.1.13). If your phone is on <strong>Mobile Cellular Data (LTE/5G)</strong>, it cannot reach this private network. Please enable Wi-Fi on your phone!
        </div>

        <div class="qr-box">
          <img src="data:image/png;base64,{qr_b64}" alt="Scan QR Code to Download APK">
        </div>

        <a href="/download/app.apk" class="btn">📥 Download Production APK (18.2 MB - ARM64)</a>
        <a href="/download/universal" class="btn-sec">📦 Download Universal APK (46.2 MB - All Devices)</a>

        <div class="instructions">
          <strong>📱 Quick Installation Guide:</strong><br>
          1. Connect your Android phone to the same Wi-Fi.<br>
          2. Tap Download above or scan the QR code.<br>
          3. Tap the downloaded APK in Notifications/Files to Install.<br>
          4. Open app & register your institutional account!
        </div>
      </div>
    </body>
    </html>
    """
    return HTMLResponse(content=html)
    return HTMLResponse(content=html)


@app.get("/")
async def root():
    return {
        "title": settings.PROJECT_NAME,
        "version": settings.VERSION,
        "status": "healthy",
        "download_hub": "/download",
        "apk_download": "/download/app.apk",
        "mobile_simulator": "/app/",
        "api_docs": f"{settings.API_V1_STR}/docs",
        "health": f"{settings.API_V1_STR}/health",
    }
