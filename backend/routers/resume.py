"""
JobBus Backend — Resume Router.

Upload and parse resumes, retrieve stored profiles.
"""

from __future__ import annotations


import os
import uuid
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File

from middleware.auth_middleware import get_current_user
from services.resume_analyzer import (
    ResumeExtractor, ResumeAnalyzer, UnsupportedFormat, EmptyResume,
    save_resume_profile, get_resume_profile,
)
from services.credential_service import get_credential_service
from models.schemas import ResumeProfile, ResumeUploadResponse
from database import get_supabase_admin


router = APIRouter(prefix="/api/resume", tags=["resume"])


async def _get_gemini_key(user_id: str) -> str:
    """Get user's decrypted Gemini API key."""
    supabase = get_supabase_admin()
    result = supabase.table("user_secrets").select("gemini_key_encrypted").eq("user_id", user_id).execute()
    if not result.data or not result.data[0].get("gemini_key_encrypted"):
        raise HTTPException(status_code=400, detail="Gemini API key not configured. Complete onboarding first.")
    cred_service = get_credential_service()
    return cred_service._decrypt(result.data[0]["gemini_key_encrypted"])


@router.post("/upload", response_model=ResumeUploadResponse)
async def upload_resume(
    file: UploadFile = File(...),
    user: dict = Depends(get_current_user),
):
    """Upload and parse a resume (PDF or DOCX)."""
    # Validate file type
    filename = file.filename or ""
    try:
        file_bytes = await file.read()
        text = ResumeExtractor.extract_text(file_bytes=file_bytes, filename=filename)
    except UnsupportedFormat as e:
        raise HTTPException(status_code=400, detail=str(e))
    except EmptyResume as e:
        raise HTTPException(status_code=400, detail=str(e))

    # Parse with AI
    api_key = await _get_gemini_key(user["user_id"])
    analyzer = ResumeAnalyzer(api_key=api_key)
    profile = await analyzer.parse(text)

    # Save to storage
    file_path = f"resumes/{user['user_id']}/{uuid.uuid4().hex}_{filename}"
    saved = save_resume_profile(user["user_id"], profile, file_path)

    return ResumeUploadResponse(
        profile=saved,
        file_path=file_path,
    )


@router.get("/profile", response_model=ResumeProfile)
async def get_my_resume(user: dict = Depends(get_current_user)):
    """Get parsed resume profile."""
    profile = get_resume_profile(user["user_id"])
    if not profile:
        raise HTTPException(status_code=404, detail="No resume uploaded yet")
    return profile


@router.post("/text", response_model=ResumeProfile)
async def save_resume_text(
    payload: dict,
    user: dict = Depends(get_current_user),
):
    """
    Accept raw resume text (paste from clipboard / onboarding wizard).
    Stores as a plain-text profile row — AI parsing happens on next upload.
    """
    text = (payload.get("text") or "").strip()
    if len(text) < 50:
        raise HTTPException(status_code=400, detail="Resume text too short (min 50 characters)")

    supabase = get_supabase_admin()
    row = {
        "user_id": user["user_id"],
        "raw_text": text,
        "name": user.get("display_name", ""),
        "role": "",
        "skills": [],
        "achievements": [],
        "email_context": f"Resume text provided by user ({len(text)} chars)",
        "file_path": None,
    }
    result = supabase.table("user_resume_profiles").upsert(row).execute()
    saved = result.data[0] if result.data else row
    return ResumeProfile(
        id=saved.get("id"),
        name=saved.get("name", ""),
        role=saved.get("role", ""),
        skills=saved.get("skills") or [],
        achievements=saved.get("achievements") or [],
        email_context=saved.get("email_context", ""),
    )
