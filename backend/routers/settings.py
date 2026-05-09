"""
JobBus Backend — Settings Router.

SMTP credentials and user preferences management.
"""

from __future__ import annotations


from fastapi import APIRouter, Depends, HTTPException

from middleware.auth_middleware import get_current_user
from services.credential_service import get_credential_service
from models.schemas import SMTPCredentialCreate, SMTPCredentialStatus


router = APIRouter(prefix="/api/settings", tags=["settings"])


@router.get("/smtp/status", response_model=SMTPCredentialStatus)
async def get_smtp_status(user: dict = Depends(get_current_user)):
    """Check SMTP credential configuration status (no secrets exposed)."""
    return get_credential_service().get_status(user["user_id"])


@router.post("/smtp/configure")
async def configure_smtp(
    request: SMTPCredentialCreate,
    user: dict = Depends(get_current_user),
):
    """Store encrypted SMTP credentials."""
    get_credential_service().store(user["user_id"], request)
    return {"message": "SMTP credentials saved successfully"}


@router.delete("/smtp")
async def delete_smtp(user: dict = Depends(get_current_user)):
    """Delete stored SMTP credentials."""
    get_credential_service().delete(user["user_id"])
    return {"message": "SMTP credentials deleted"}


@router.post("/smtp/test")
async def test_smtp(user: dict = Depends(get_current_user)):
    """Test SMTP connectivity by sending a test email to self."""
    from services.smtp_sender import get_smtp_sender

    try:
        creds = get_credential_service().get_decrypted(user["user_id"])
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

    sender = get_smtp_sender()
    result = await sender.send(
        user_id=user["user_id"],
        to_email=creds["smtp_user"],
        subject="JobBus — SMTP Test ✓",
        body="Your email configuration is working correctly. You're all set!",
    )

    if result.success:
        return {"message": "Test email sent successfully!", "to": creds["smtp_user"]}
    else:
        raise HTTPException(
            status_code=400,
            detail=f"SMTP test failed: {result.error_message}",
        )
