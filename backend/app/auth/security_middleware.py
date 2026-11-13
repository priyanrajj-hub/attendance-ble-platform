import time
import re
from typing import Dict, Tuple
from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse

# In-memory sliding window rate limiter for DDoS and brute-force mitigation
# Key: client_ip, Value: (request_count, window_start_time)
RATE_LIMIT_STORE: Dict[str, Tuple[int, float]] = {}
WINDOW_SIZE_SECONDS = 60.0
MAX_REQUESTS_PER_WINDOW = 120  # Max 120 requests/minute per client IP
MAX_AUTH_REQUESTS_PER_WINDOW = 30  # Max 30 auth requests/minute per client IP


class EnterpriseSecurityHeadersMiddleware(BaseHTTPMiddleware):
    """
    OWASP-compliant enterprise security headers middleware.
    Protects against Clickjacking, MIME-sniffing, XSS, and Protocol Downgrades.
    """

    async def dispatch(self, request: Request, call_next):
        response: Response = await call_next(request)

        # 1. Clickjacking Defense (Permit framing only on same origin for simulator)
        response.headers["X-Frame-Options"] = "SAMEORIGIN"

        # 2. MIME-Type Sniffing Protection
        response.headers["X-Content-Type-Options"] = "nosniff"

        # 3. Cross-Site Scripting (XSS) Legacy Protection
        response.headers["X-XSS-Protection"] = "1; mode=block"

        # 4. Referrer Policy
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"

        # 5. Restrict Dangerous Browser Features
        response.headers["Permissions-Policy"] = (
            "camera=(), microphone=(), payment=(), usb=()"
        )

        # 6. HTTP Strict Transport Security (HSTS)
        response.headers["Strict-Transport-Security"] = (
            "max-age=31536000; includeSubDomains"
        )

        # 7. Cache-Control for sensitive API endpoints
        if request.url.path.startswith("/api/"):
            response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate"
            response.headers["Pragma"] = "no-cache"

        return response


class RateLimiterAntiDDoSMiddleware(BaseHTTPMiddleware):
    """
    In-memory rate limiter to mitigate DDoS, API flooding, and credential stuffing.
    Enforces stricter thresholds on sensitive endpoints (e.g. /auth).
    """

    async def dispatch(self, request: Request, call_next):
        # Static assets, simulator, and binary downloads are exempt from API rate limiting
        if request.url.path.startswith("/download") or request.url.path.startswith("/app"):
            return await call_next(request)

        # Extract client IP (handling reverse proxies safely)
        forwarded_for = request.headers.get("X-Forwarded-For")
        if forwarded_for:
            client_ip = forwarded_for.split(",")[0].strip()
        else:
            client_ip = request.client.host if request.client else "127.0.0.1"

        now = time.time()
        is_auth_route = "/auth" in request.url.path or "/sessions/start" in request.url.path
        limit = MAX_AUTH_REQUESTS_PER_WINDOW if is_auth_route else MAX_REQUESTS_PER_WINDOW

        bucket_key = f"{client_ip}:{ 'auth' if is_auth_route else 'api' }"
        count, window_start = RATE_LIMIT_STORE.get(bucket_key, (0, now))

        if now - window_start > WINDOW_SIZE_SECONDS:
            # Reset window
            RATE_LIMIT_STORE[bucket_key] = (1, now)
        else:
            if count >= limit:
                retry_after = int(WINDOW_SIZE_SECONDS - (now - window_start)) + 1
                return JSONResponse(
                    status_code=429,
                    content={
                        "error": "Too Many Requests",
                        "detail": f"Rate limit exceeded ({limit} requests/{int(WINDOW_SIZE_SECONDS)}s). Please retry after {retry_after}s.",
                        "client_ip": client_ip,
                    },
                    headers={"Retry-After": str(retry_after)},
                )
            RATE_LIMIT_STORE[bucket_key] = (count + 1, window_start)

        # Clean old buckets periodically
        if len(RATE_LIMIT_STORE) > 10000:
            expired_keys = [
                k for k, (_, t) in RATE_LIMIT_STORE.items() if now - t > WINDOW_SIZE_SECONDS
            ]
            for k in expired_keys:
                RATE_LIMIT_STORE.pop(k, None)

        return await call_next(request)


class PathTraversalAndInputDefenseMiddleware(BaseHTTPMiddleware):
    """
    Sanitizes requests to block Path Traversal, Null-Byte Injection,
    and Malicious Directory Crawlers.
    """

    TRAVERSAL_PATTERN = re.compile(r"(\.\./|\.\.\\|%2e%2e|%252e%252e)", re.IGNORECASE)

    async def dispatch(self, request: Request, call_next):
        # Inspect raw query params and URL path for traversal attacks
        raw_url = str(request.url)
        if self.TRAVERSAL_PATTERN.search(raw_url) or "\x00" in raw_url:
            return JSONResponse(
                status_code=400,
                content={
                    "error": "Bad Request",
                    "detail": "Path traversal or malformed characters detected in request URI.",
                },
            )

        return await call_next(request)
