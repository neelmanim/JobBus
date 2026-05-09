"""
JobBus Backend — Outreach Angle Engine.

Determines the best outreach angle BEFORE generating any email.
The angle drives the email strategy, hook, and tone.
"""

from __future__ import annotations


from models.enums import AngleType
from models.schemas import AngleResult, SignalResult


class OutreachAngleEngine:
    """Determines the best outreach angle for an opportunity."""

    def determine_angle(self, opportunity: dict, resume_profile: dict) -> AngleResult:
        """Analyze signals and determine the best outreach angle.

        Returns the angle type, hook guidance, reasoning, and signals used.
        """
        signals = opportunity.get("signals", {})
        signals_used = []

        # Evaluate each signal's contribution to angle selection
        hiring_active = signals.get("hiring", {}).get("active", False) if isinstance(signals.get("hiring"), dict) else signals.get("hiring", False)
        funding_data = signals.get("funding", {})
        recently_funded = funding_data.get("score", 0) > 0 if isinstance(funding_data, dict) else signals.get("recently_funded", False)

        # Decision tree for angle selection
        if hiring_active:
            return self._build_hiring_angle(opportunity, resume_profile, signals, signals_used)
        elif recently_funded:
            return self._build_growth_angle(opportunity, resume_profile, signals, signals_used)
        else:
            return self._build_curiosity_angle(opportunity, resume_profile, signals, signals_used)

    def _build_hiring_angle(self, opportunity, resume_profile, signals, signals_used):
        role = opportunity.get("role_title", "the role")
        company = opportunity.get("company_name", "the company")
        skills = resume_profile.get("skills", [])

        signals_used.append({
            "signal": "hiring",
            "contribution": f"Active opening for {role}",
        })

        matching_skills = signals.get("role_match_keywords", [])
        if matching_skills:
            signals_used.append({
                "signal": "role_alignment",
                "contribution": f"Skills match: {', '.join(matching_skills[:3])}",
            })

        hook_guidance = (
            f"Reference the {role} opening at {company}. "
            f"Connect a specific skill ({', '.join(skills[:2])}) to what the role needs. "
            f"Do NOT say 'I saw your job posting' — make a specific observation instead."
        )

        reasoning = (
            f"{company} is actively hiring for {role}, which aligns with the candidate's "
            f"background in {', '.join(skills[:3])}. A hiring-based angle gives the strongest "
            f"reason to reach out — there's an actual seat to fill."
        )

        return AngleResult(
            angle_type=AngleType.HIRING_BASED,
            hook_guidance=hook_guidance,
            reasoning=reasoning,
            signals_used=signals_used,
        )

    def _build_growth_angle(self, opportunity, resume_profile, signals, signals_used):
        company = opportunity.get("company_name", "the company")
        funding_info = signals.get("funding", {})
        funding_reason = funding_info.get("reason", "recent funding") if isinstance(funding_info, dict) else "recent growth"

        signals_used.append({
            "signal": "funding",
            "contribution": funding_reason,
        })

        hook_guidance = (
            f"Reference {company}'s growth trajectory ({funding_reason}). "
            f"Connect how the candidate's experience could help scale the engineering team. "
            f"Position the outreach as 'growth creates new challenges I can help with.'"
        )

        reasoning = (
            f"{company} has {funding_reason}, suggesting rapid hiring ahead. "
            f"Even without a specific posting, funded companies are actively building teams."
        )

        return AngleResult(
            angle_type=AngleType.GROWTH_BASED,
            hook_guidance=hook_guidance,
            reasoning=reasoning,
            signals_used=signals_used,
        )

    def _build_curiosity_angle(self, opportunity, resume_profile, signals, signals_used):
        company = opportunity.get("company_name", "the company")
        role = opportunity.get("role_title", "")

        hook_guidance = (
            f"Express genuine interest in {company}'s product or engineering challenges. "
            f"Reference something specific about the company (tech stack, blog post, product). "
            f"Frame as 'I'm interested in what you're building' — not job-seeking."
        )

        reasoning = (
            f"No strong hiring or funding signal for {company}. Using curiosity-based "
            f"angle — expressing genuine interest is the most authentic approach when "
            f"there's no direct opening or growth trigger."
        )

        return AngleResult(
            angle_type=AngleType.CURIOSITY_BASED,
            hook_guidance=hook_guidance,
            reasoning=reasoning,
            signals_used=signals_used,
        )

    @staticmethod
    def build_problem_angle(company: str, problem_context: str) -> AngleResult:
        """Build a problem-based angle (for future use with richer signal data)."""
        return AngleResult(
            angle_type=AngleType.PROBLEM_BASED,
            hook_guidance=(
                f"Reference a specific challenge {company} might face: {problem_context}. "
                f"Position the candidate as someone who has solved this exact problem before."
            ),
            reasoning=f"Problem-based approach for {company} based on: {problem_context}",
            signals_used=[{"signal": "problem", "contribution": problem_context}],
        )
