"""
JobBus Backend — Opportunity Scorer.

Weighted signal-based scoring engine that ranks opportunities on a 0-100 scale.

Signals & Weights:
  A. Hiring Activity  — 30 points max (highest)
  B. Funding/Growth   — 20 points max
  C. Persona Relevance — 20 points max
  D. Role Alignment    — 15 points max
  E. Company Fit       — 10 points max
  F. Activity Signal   — 5 points max
"""

from __future__ import annotations


from dataclasses import dataclass, field
from typing import Optional

from models.enums import OpportunityTier, AngleType
from models.schemas import SignalResult, OpportunityScore


# ═══════════════════════════════════════════════════════════════
# SIGNAL EVALUATORS
# ═══════════════════════════════════════════════════════════════

class HiringActivitySignal:
    """Signal A — Hiring Activity (30 points max)."""
    MAX_SCORE = 30

    def evaluate(
        self,
        job_url: Optional[str] = None,
        role_title: Optional[str] = None,
        resume_skills: list[str] = None,
    ) -> SignalResult:
        if not job_url:
            return SignalResult(signal="hiring", score=0, reason="No job posting found", active=False)

        base_score = 20  # Active posting
        reason_parts = ["Active job posting found"]

        # Bonus for skill overlap in role
        if resume_skills and role_title:
            role_lower = (role_title or "").lower()
            matching = [s for s in (resume_skills or []) if s.lower() in role_lower]
            if matching:
                base_score += min(len(matching) * 3, 10)
                reason_parts.append(f"Role matches skills: {', '.join(matching[:3])}")
            else:
                reason_parts.append("Role found but limited skill overlap")

        return SignalResult(
            signal="hiring",
            score=min(base_score, self.MAX_SCORE),
            reason=". ".join(reason_parts),
            active=True,
        )


class FundingGrowthSignal:
    """Signal B — Funding/Growth (20 points max)."""
    MAX_SCORE = 20

    ROUND_SCORES = {
        "seed": 10,
        "series a": 15,
        "series b": 18,
        "series c": 20,
        "series d": 20,
        "ipo": 12,
    }

    def evaluate(
        self,
        recently_funded: bool = False,
        funding_round: Optional[str] = None,
    ) -> SignalResult:
        if not recently_funded:
            return SignalResult(signal="funding", score=0, reason="No recent funding data", active=False)

        round_lower = (funding_round or "").lower().strip()
        score = self.ROUND_SCORES.get(round_lower, 12)
        reason = f"Recently funded ({funding_round})" if funding_round else "Recently funded"

        return SignalResult(
            signal="funding",
            score=min(score, self.MAX_SCORE),
            reason=reason,
            active=True,
        )


class PersonaRelevanceSignal:
    """Signal C — Persona Relevance (20 points max)."""
    MAX_SCORE = 20

    PERSONA_SCORES = {
        "hiring_manager": 20,
        "vp": 18,
        "team_lead": 15,
        "director": 14,
        "founder": 12,
        "cto": 12,
        "ceo": 10,
        "recruiter": 6,
        "hr": 5,
        "other": 3,
    }

    TITLE_TO_PERSONA = {
        "engineering manager": "hiring_manager",
        "vp of engineering": "vp",
        "vice president": "vp",
        "senior tech lead": "team_lead",
        "tech lead": "team_lead",
        "team lead": "team_lead",
        "director": "director",
        "cto": "cto",
        "chief technology": "cto",
        "founder": "founder",
        "co-founder": "founder",
        "ceo": "ceo",
        "chief executive": "ceo",
        "recruiter": "recruiter",
        "technical recruiter": "recruiter",
        "talent": "recruiter",
        "hr ": "hr",
        "human resources": "hr",
        "people operations": "hr",
    }

    def evaluate(self, title: str = "") -> SignalResult:
        title_lower = title.lower().strip()

        persona_type = "other"
        for keyword, ptype in self.TITLE_TO_PERSONA.items():
            if keyword in title_lower:
                persona_type = ptype
                break

        score = self.PERSONA_SCORES.get(persona_type, 3)
        return SignalResult(
            signal="persona",
            score=min(score, self.MAX_SCORE),
            reason=f"{title} → {persona_type.replace('_', ' ').title()}",
            active=True,
        )


class RoleAlignmentSignal:
    """Signal D — Role Alignment (15 points max)."""
    MAX_SCORE = 15

    def evaluate(
        self,
        resume_skills: list[str] = None,
        role_keywords: list[str] = None,
    ) -> SignalResult:
        if not resume_skills or not role_keywords:
            return SignalResult(signal="role_alignment", score=0, reason="Insufficient data for alignment", active=False)

        resume_set = {s.lower() for s in resume_skills}
        role_set = {k.lower() for k in role_keywords}

        overlap = resume_set & role_set
        match_pct = len(overlap) / max(len(role_set), 1)

        score = round(match_pct * self.MAX_SCORE)
        matching = [s for s in resume_skills if s.lower() in overlap]

        return SignalResult(
            signal="role_alignment",
            score=min(score, self.MAX_SCORE),
            reason=f"{len(overlap)}/{len(role_set)} skills match ({', '.join(matching[:4])})" if overlap else "No skill overlap",
            active=bool(overlap),
        )


class CompanyFitSignal:
    """Signal E — Company Fit (10 points max)."""
    MAX_SCORE = 10

    def evaluate(
        self,
        company_size: Optional[str] = None,
        industry: Optional[str] = None,
        remote_friendly: Optional[bool] = None,
        preferences: dict = None,
    ) -> SignalResult:
        if not preferences:
            return SignalResult(signal="company_fit", score=0, reason="No preferences set", active=False)

        score = 0
        reasons = []

        # Size match
        if company_size and preferences.get("company_size_preference"):
            if company_size in preferences["company_size_preference"]:
                score += 4
                reasons.append(f"Size match ({company_size})")

        # Industry match
        if industry and preferences.get("industry_preference"):
            if any(ind.lower() in industry.lower() for ind in preferences["industry_preference"]):
                score += 3
                reasons.append(f"Industry match ({industry})")

        # Remote match
        if remote_friendly is not None and preferences.get("remote_preference"):
            if remote_friendly == preferences["remote_preference"]:
                score += 3
                reasons.append("Remote preference match")

        return SignalResult(
            signal="company_fit",
            score=min(score, self.MAX_SCORE),
            reason=". ".join(reasons) if reasons else "No preference matches",
            active=score > 0,
        )


# ═══════════════════════════════════════════════════════════════
# MAIN SCORER
# ═══════════════════════════════════════════════════════════════

class OpportunityScorer:
    """Main scoring engine — combines all signals into a 0-100 score."""

    def __init__(self):
        self.hiring_signal = HiringActivitySignal()
        self.funding_signal = FundingGrowthSignal()
        self.persona_signal = PersonaRelevanceSignal()
        self.role_signal = RoleAlignmentSignal()
        self.fit_signal = CompanyFitSignal()

    def score(
        self,
        opportunity: dict,
        resume_profile: dict,
        user_preferences: dict = None,
    ) -> OpportunityScore:
        """Score an opportunity across all signals."""
        signals = opportunity.get("signals", {})

        results = [
            self.hiring_signal.evaluate(
                job_url=opportunity.get("job_url"),
                role_title=opportunity.get("role_title"),
                resume_skills=resume_profile.get("skills", []),
            ),
            self.funding_signal.evaluate(
                recently_funded=signals.get("recently_funded", False),
                funding_round=signals.get("funding_round"),
            ),
            self.persona_signal.evaluate(
                title=signals.get("persona_type", signals.get("contact_title", "")),
            ),
            self.role_signal.evaluate(
                resume_skills=resume_profile.get("skills", []),
                role_keywords=signals.get("role_match_keywords", []),
            ),
            self.fit_signal.evaluate(
                company_size=signals.get("company_size"),
                industry=signals.get("industry"),
                remote_friendly=signals.get("remote_friendly"),
                preferences=user_preferences or {},
            ),
        ]

        total = sum(r.score for r in results)
        total = min(total, 100)

        if total >= 70:
            tier = OpportunityTier.HIGH
        elif total >= 40:
            tier = OpportunityTier.MEDIUM
        else:
            tier = OpportunityTier.LOW

        return OpportunityScore(
            total=total,
            tier=tier,
            explanations=results,
        )

    def get_top_picks(
        self,
        opportunities: list[dict],
        resume_profile: dict,
        user_preferences: dict = None,
        max_count: int = 20,
    ) -> list[dict]:
        """Get curated top opportunities, sorted by score, deduplicated."""
        scored = []
        seen = set()

        for opp in opportunities:
            # Deduplicate by company + role
            key = (
                opp.get("company_name", "").lower().strip(),
                opp.get("role_title", "").lower().strip(),
            )
            if key in seen:
                continue
            seen.add(key)

            score = self.score(opp, resume_profile, user_preferences)
            if score.tier != OpportunityTier.LOW:
                scored.append({**opp, "_score": score})

        # Sort by total score descending
        scored.sort(key=lambda x: x["_score"].total, reverse=True)
        return scored[:max_count]

    @staticmethod
    def recommend_angle(score: OpportunityScore, signals: dict) -> AngleType:
        """Recommend outreach angle based on signal results."""
        hiring_result = next((r for r in score.explanations if r.signal == "hiring"), None)
        funding_result = next((r for r in score.explanations if r.signal == "funding"), None)

        if hiring_result and hiring_result.active:
            return AngleType.HIRING_BASED
        elif funding_result and funding_result.active:
            return AngleType.GROWTH_BASED
        else:
            return AngleType.CURIOSITY_BASED
