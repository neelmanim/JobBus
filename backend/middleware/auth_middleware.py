"""
JobBus Backend — Auth Middleware.

Verifies Supabase JWT tokens and injects the authenticated user
into FastAPI request state.
"""

from __future__ import annotations


from fastapi import Request, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt, JWTError, ExpiredSignatureError
from config import get_settings
from database import get_supabase_admin


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

    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=[settings.jwt_algorithm],
            audience="authenticated",
        )
    except ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has expired",
        )
    except JWTError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token: {str(e)}",
        )

    user_id = payload.get("sub")
    email = payload.get("email")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token missing user ID",
        )

    # Check if user is active
    supabase = get_supabase_admin()
    result = supabase.table("user_profiles").select("*").eq("user_id", user_id).execute()

    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User profile not found. Please complete onboarding.",
        )

    profile = result.data[0]
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
