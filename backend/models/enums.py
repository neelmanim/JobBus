"""Enums for the JobBus application."""

from enum import Enum


class UserMode(str, Enum):
    """User experience mode."""
    BEGINNER = "beginner"
    ADVANCED = "advanced"


class CampaignStatus(str, Enum):
    """Campaign lifecycle states."""
    DRAFT = "draft"
    REVIEWING = "reviewing"
    APPROVED = "approved"
    SENDING = "sending"
    PAUSED = "paused"
    COMPLETED = "completed"


class ContactStatus(str, Enum):
    """Per-contact status within a campaign."""
    PENDING = "pending"
    DRAFTED = "drafted"
    SENT = "sent"
    REPLIED = "replied"
    BOUNCED = "bounced"
    INTERVIEW = "interview"
    NO_RESPONSE = "no_response"


class OpportunityTier(str, Enum):
    """Opportunity score tier."""
    HIGH = "high"       # 70+
    MEDIUM = "medium"   # 40-69
    LOW = "low"         # <40


class OpportunityStatus(str, Enum):
    """Opportunity tracking status."""
    DISCOVERED = "discovered"
    SHORTLISTED = "shortlisted"
    OUTREACH_SENT = "outreach_sent"
    REPLIED = "replied"
    INTERVIEW = "interview"
    REJECTED = "rejected"
    ARCHIVED = "archived"


class AngleType(str, Enum):
    """Outreach angle types."""
    HIRING_BASED = "hiring_based"
    PROBLEM_BASED = "problem_based"
    CURIOSITY_BASED = "curiosity_based"
    GROWTH_BASED = "growth_based"


class FollowUpSequence(int, Enum):
    """Follow-up sequence number."""
    FIRST = 1
    SECOND = 2


class GuidanceSeverity(str, Enum):
    """Guidance card severity levels."""
    INFO = "info"
    WARNING = "warning"
    CRITICAL = "critical"


class OutcomeType(str, Enum):
    """Outcome tracking types."""
    REPLY = "reply"
    INTERVIEW = "interview"
    BOUNCE = "bounce"
    NO_RESPONSE = "no_response"
