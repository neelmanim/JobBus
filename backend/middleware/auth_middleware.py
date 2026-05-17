"""
JobBus Backend — Auth Middleware.

Verifies Supabase JWT tokens and injects the authenticated user
into FastAPI request state.

Supports both:
  - ES256 (Supabase v2+, public key via JWKS)
  - HS256 (legacy, shared JWT secret)
"""

from __future__ import annotations

import time
import httpx
from fastapi import Request, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt, JWTError, ExpiredSignatureError
from config import get_settings
from database import get_supabase_admin


# ── JWKS cache ───────────────────────────────────────────────────
# Cache JWKS keys to avoid fetching on every request
_jwks_cache: dict = {}


# ── User profile TTL cache ────────────────────────────────────────
# Eliminates the Supabase round-trip (~200-500ms) on every API call.
# TTL = 5 minutes. Max 1000 entries (covers most single-user sessions).
_profile_cache: dict[str, tuple[dict, float]] = {}  # user_id -> (profile, expires_at)
_PROFILE_TTL = 300  # seconds
_CACHE_MAX    = 1000


def _get_cached_profile(user_id: str) -> dict | None:
    entry = _profile_cache.get(user_id)
    if entry and time.monotonic() < entry[1]:
        return entry[0]
    _profile_cache.pop(user_id, None)
    return None


def _set_cached_profile(user_id: str, profile: dict) -> None:
    if len(_profile_cache) >= _CACHE_MAX:
        # Evict oldest 20% when full
        oldest = sorted(_profile_cache.items(), key=lambda x: x[1][1])[:_CACHE_MAX // 5]
        for k, _ in oldest:
            _profile_cache.pop(k, None)
    _profile_cache[user_id] = (profile, time.monotonic() + _PROFILE_TTL)


def invalidate_user_cache(user_id: str) -> None:
    """Call this whenever a user's profile is updated so the cache refreshes."""
    _profile_cache.pop(user_id, None)


def _get_supabase_jwks(supabase_url: str) -> list:
    """Fetch Supabase JWKS public keys (cached)."""
    global _jwks_cache
    if supabase_url not in _jwks_cache:
        try:
            resp = httpx.get(f"{supabase_url}/auth/v1/.well-known/jwks.json", timeout=5)
            resp.raise_for_status()
            _jwks_cache[supabase_url] = resp.json().get("keys", [])
        except Exception:
            _jwks_cache[supabase_url] = []
    return _jwks_cache[supabase_url]


security = HTTPBearer()


async def get_current_user(request: Request) -> dict:
    """Extract and verify the JWT from the Authorization header.
    
    Returns the user dict with at minimum:
        - user_id: str
        - email: str
    
    Raises HTTPException 401 if token is missing/invalid/expired.
    Raises HTTPException 403 if user is deactivated.
    """
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid Authorization header",
        )

    token = auth_header.split(" ", 1)[1]
    settings = get_settings()

    payload = None
    last_error = "Unknown error"

    # 1) Try ES256 via Supabase JWKS (Supabase v2+)
    jwks_keys = _get_supabase_jwks(settings.supabase_url)
    for jwk_key in jwks_keys:
        try:
            payload = jwt.decode(
                token,
                jwk_key,
                algorithms=["ES256", "RS256"],
                audience="authenticated",
            )
            break  # Success
        except ExpiredSignatureError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token has expired",
            )
        except JWTError as e:
            last_error = str(e)
            continue

    # 2) Fall back to HS256 with shared JWT secret (legacy)
    if payload is None and settings.jwt_secret:
        try:
            payload = jwt.decode(
                token,
                settings.jwt_secret,
                algorithms=["HS256"],
                audience="authenticated",
            )
        except ExpiredSignatureError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token has expired",
            )
        except JWTError as e:
            last_error = str(e)

    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token: {last_error}",
        )

    user_id = payload.get("sub")
    email = payload.get("email")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token missing user ID",
        )

    # ── Profile lookup with TTL cache ─────────────────────────────
    # Cache hit: skip Supabase entirely (~200-500ms saved per request)
    profile = _get_cached_profile(user_id)
    if profile is None:
        supabase = get_supabase_admin()
        result = supabase.table("user_profiles").select("*").eq("user_id", user_id).execute()

        if not result.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User profile not found. Please complete onboarding.",
            )

        profile = result.data[0]
        _set_cached_profile(user_id, profile)

    if not profile.get("is_active", True):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account has been deactivated. Contact admin.",
        )

    return {
        "user_id": user_id,
        "email": email,
        **profile,
    }


async def get_jwt_user(request: Request) -> dict:
    """Validate JWT and return basic user info — does NOT require a profile.

    Use this for endpoints that must work before a profile exists (e.g. /register).
    Returns: {"user_id": str, "email": str}
    """
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid Authorization header",
        )

    token = auth_header.split(" ", 1)[1]
    settings = get_settings()

    payload = None
    last_error = "Unknown error"

    jwks_keys = _get_supabase_jwks(settings.supabase_url)
    for jwk_key in jwks_keys:
        try:
            payload = jwt.decode(token, jwk_key, algorithms=["ES256", "RS256"], audience="authenticated")
            break
        except ExpiredSignatureError:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token has expired")
        except JWTError as e:
            last_error = str(e)

    if payload is None and settings.jwt_secret:
        try:
            payload = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"], audience="authenticated")
        except ExpiredSignatureError:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token has expired")
        except JWTError as e:
            last_error = str(e)

    if payload is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=f"Invalid token: {last_error}")

    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token missing user ID")

    return {
        "user_id": user_id,
        "email": payload.get("email", ""),
        "display_name": payload.get("user_metadata", {}).get("full_name", ""),
        "avatar_url": payload.get("user_metadata", {}).get("avatar_url", ""),
    }


async def require_admin(request: Request) -> dict:

    """Require the current user to be an admin.
    
    Returns the user dict if admin, raises 403 otherwise.
    """
    user = await get_current_user(request)
    if not user.get("is_admin", False):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required",
        )
    return user
