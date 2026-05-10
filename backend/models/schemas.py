"""
JobBus Backend — Pydantic Schemas.

Request/response models for all API endpoints.
"""

from __future__ import annotations
from pydantic import BaseModel, Field, EmailStr
from datetime import datetime
from typing import Optional
from models.enums import (
    UserMode, CampaignStatus, ContactStatus, OpportunityTier,
    OpportunityStatus, AngleType, GuidanceSeverity, OutcomeType,
)


# ═══════════════════════════════════════════════════════════════
# AUTH & USERS
# ═══════════════════════════════════════════════════════════════

class InviteCodeCreate(BaseModel):
    """Request to create invite code(s)."""
    count: int = Field(1, ge=1, le=50, description="Number of codes to generate")
    note: Optional[str] = Field(None, max_length=200)
    expires_in_days: Optional[int] = Field(None, ge=1, le=90)


class InviteCodeResponse(BaseModel):
    """Single invite code response."""
    id: str
    code: str
    created_by: str
    used: bool
    used_by: Optional[str] = None
    note: Optional[str] = None
    expires_at: Optional[datetime] = None
    created_at: datetime


class InviteValidationResult(BaseModel):
    """Result of validating an invite code."""
    valid: bool
    reason: Optional[str] = None


class UserProfileResponse(BaseModel):
    """User profile response."""
    user_id: str
    display_name: str
    avatar_url: Optional[str] = None
    email: str
    mode: UserMode = UserMode.BEGINNER
    is_admin: bool = False
    is_active: bool = True
    last_login_at: Optional[datetime] = None
    created_at: datetime


class UserModeUpdate(BaseModel):
    """Request to update user mode."""
    mode: UserMode


class OnboardingComplete(BaseModel):
    """
    Legacy minimal onboarding schema (kept for backward compatibility).
    The comprehensive wizard uses OnboardingCompleteRequest in routers/auth.py.
    """
    gemini_api_key: str = Field("", description="Gemini API key (optional in new flow)")
    mode: UserMode = UserMode.BEGINNER


# ═══════════════════════════════════════════════════════════════
# ADMIN
# ═══════════════════════════════════════════════════════════════

class AdminUserListItem(BaseModel):
    """User item in admin user list."""
    user_id: str
    display_name: str
    email: str
    mode: UserMode
    is_active: bool
    is_admin: bool
    last_login_at: Optional[datetime] = None
    campaigns_count: int = 0
    total_sent: int = 0
    created_at: datetime


class AdminUserActivity(BaseModel):
    """Detailed user activity for admin view."""
    user_id: str
    display_name: str
    last_login_at: Optional[datetime] = None
    campaigns_count: int = 0
    total_sent: int = 0
    total_replies: int = 0
    total_interviews: int = 0
    active_campaigns: int = 0


# ═══════════════════════════════════════════════════════════════
# RESUME
# ═══════════════════════════════════════════════════════════════

class ResumeProfile(BaseModel):
    """Parsed resume profile."""
    id: Optional[str] = None
    name: str
    role: str
    skills: list[str] = []
    achievements: list[str] = []
    email_context: str = ""


class ResumeUploadResponse(BaseModel):
    """Response after resume upload + parse."""
    profile: ResumeProfile
    file_path: str
    message: str = "Resume parsed successfully"


# ═══════════════════════════════════════════════════════════════
# CREDENTIALS (SMTP)
# ═══════════════════════════════════════════════════════════════

class SMTPCredentialCreate(BaseModel):
    """Request to store SMTP credentials."""
    smtp_host: str = Field("smtp.gmail.com", description="SMTP server hostname")
    smtp_port: int = Field(587, description="SMTP server port")
    smtp_user: str = Field(..., description="Email address (e.g., user@gmail.com)")
    smtp_pass: str = Field(..., description="App password (NOT regular password)")
    sender_name: Optional[str] = Field(None, description="Display name for sent emails")


class SMTPCredentialStatus(BaseModel):
    """Status of stored SMTP credentials (no secrets exposed)."""
    configured: bool
    smtp_host: Optional[str] = None
    smtp_user: Optional[str] = None
    sender_name: Optional[str] = None


# ═══════════════════════════════════════════════════════════════
# OPPORTUNITIES
# ═══════════════════════════════════════════════════════════════

class SignalResult(BaseModel):
    """A single signal evaluation result."""
    signal: str
    score: float
    reason: str
    active: bool = True


class OpportunityScore(BaseModel):
    """Complete opportunity scoring result."""
    total: float = Field(..., ge=0, le=100)
    tier: OpportunityTier
    explanations: list[SignalResult] = []


class OpportunityResponse(BaseModel):
    """Single opportunity response."""
    id: str
    company_name: str
    role_title: str
    job_url: Optional[str] = None
    score: float
    tier: OpportunityTier
    signals: dict = {}
    recommended_angle: Optional[AngleType] = None
    status: OpportunityStatus = OpportunityStatus.DISCOVERED
    created_at: datetime


# ═══════════════════════════════════════════════════════════════
# OUTREACH
# ═══════════════════════════════════════════════════════════════

class AngleResult(BaseModel):
    """Result of angle determination."""
    angle_type: AngleType
    hook_guidance: str
    reasoning: str
    signals_used: list[dict] = []


class EmailDraft(BaseModel):
    """Generated email draft."""
    id: Optional[str] = None
    contact_id: str
    subject: str
    body: str
    angle_type: AngleType
    angle_reasoning: str
    signals_used: list[dict] = []
    quality_score: Optional[float] = None


class QualityCheckResult(BaseModel):
    """Single quality check result."""
    name: str
    passed: bool
    detail: str


class QualityScoreResult(BaseModel):
    """Complete quality scoring result."""
    total: float = Field(..., ge=0, le=10)
    checks: list[QualityCheckResult] = []


# ═══════════════════════════════════════════════════════════════
# CAMPAIGNS
# ═══════════════════════════════════════════════════════════════

class CampaignCreate(BaseModel):
    """Request to create a new campaign."""
    name: str = Field(..., min_length=1, max_length=100)
    opportunity_id: Optional[str] = None


class CampaignResponse(BaseModel):
    """Campaign response."""
    id: str
    name: str
    status: CampaignStatus
    contacts_count: int = 0
    sent_count: int = 0
    reply_count: int = 0
    interview_count: int = 0
    bounce_count: int = 0
    created_at: datetime


class CampaignAnalytics(BaseModel):
    """Campaign-level analytics."""
    sent: int = 0
    replied: int = 0
    bounced: int = 0
    interviews: int = 0
    no_response: int = 0
    reply_rate: float = 0.0
    bounce_rate: float = 0.0
    interview_conversion: float = 0.0


# ═══════════════════════════════════════════════════════════════
# GUIDANCE
# ═══════════════════════════════════════════════════════════════

class GuidanceCard(BaseModel):
    """A single guidance advisory card."""
    type: str
    severity: GuidanceSeverity
    message: str
    action_text: Optional[str] = None
    dismissed: bool = False


# ═══════════════════════════════════════════════════════════════
# COMMON
# ═══════════════════════════════════════════════════════════════

class HealthResponse(BaseModel):
    """Health check response."""
    status: str = "ok"
    version: str
    environment: str


class ErrorResponse(BaseModel):
    """Standard error response."""
    error: str
    detail: Optional[str] = None
