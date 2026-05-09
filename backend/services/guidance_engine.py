"""
JobBus Backend — Guidance Engine.

Advisory system that coaches users with contextual, non-intrusive guidance cards.
"""

from __future__ import annotations


from models.schemas import GuidanceCard
from models.enums import GuidanceSeverity


class GuidanceEngine:
    """Evaluates user actions and generates advisory guidance cards."""

    MAX_ACTIVE_CARDS = 3

    def evaluate_contacts(self, contacts: list[dict]) -> list[GuidanceCard]:
        """Evaluate contact selection for potential issues."""
        cards = []
        if not contacts:
            return cards

        # Check recruiter ratio
        recruiter_count = sum(
            1 for c in contacts
            if c.get("persona_type", "").lower() in ("recruiter", "hr")
        )
        ratio = recruiter_count / len(contacts) if contacts else 0

        if ratio > 0.5:
            cards.append(GuidanceCard(
                type="too_many_recruiters",
                severity=GuidanceSeverity.WARNING,
                message=(
                    f"{recruiter_count}/{len(contacts)} of your contacts are recruiters. "
                    f"Hiring managers and team leads typically have more influence over hiring "
                    f"decisions. Consider adding more decision-makers to your list."
                ),
                action_text="Filter by Hiring Managers",
            ))

        return cards[:self.MAX_ACTIVE_CARDS]

    def evaluate_opportunity_selection(self, opportunities: list[dict]) -> list[GuidanceCard]:
        """Evaluate opportunity selection quality."""
        cards = []
        if not opportunities:
            return cards

        low_score_count = sum(1 for o in opportunities if o.get("score", 0) < 40)
        ratio = low_score_count / len(opportunities)

        if ratio > 0.5:
            cards.append(GuidanceCard(
                type="low_opportunity_scores",
                severity=GuidanceSeverity.WARNING,
                message=(
                    f"{low_score_count}/{len(opportunities)} selected opportunities have weak alignment "
                    f"(score < 40). These are unlikely to convert. Focus on your top-scoring "
                    f"opportunities for better results."
                ),
                action_text="View Top Picks",
            ))

        return cards[:self.MAX_ACTIVE_CARDS]

    def evaluate_drafts(self, drafts: list[dict]) -> list[GuidanceCard]:
        """Evaluate draft batch for repetitiveness."""
        cards = []
        if len(drafts) < 3:
            return cards

        # Check opening similarity
        openings = []
        for d in drafts:
            body = d.get("body", "")
            lines = [l.strip() for l in body.split("\n") if l.strip()]
            opening = lines[1] if len(lines) > 1 else lines[0] if lines else ""
            openings.append(opening[:40].lower())

        # Count similar openings (>70% match = repetitive)
        if openings:
            from collections import Counter
            most_common = Counter(openings).most_common(1)[0]
            if most_common[1] / len(openings) > 0.7:
                cards.append(GuidanceCard(
                    type="repetitive_emails",
                    severity=GuidanceSeverity.WARNING,
                    message=(
                        f"{most_common[1]}/{len(drafts)} emails start with similar openings. "
                        f"This increases spam risk and looks automated. Try regenerating "
                        f"with different angles or editing manually."
                    ),
                    action_text="Regenerate Drafts",
                ))

        return cards[:self.MAX_ACTIVE_CARDS]

    def evaluate_campaign(self, campaign_state: dict) -> list[GuidanceCard]:
        """Evaluate campaign state for actionable advice."""
        cards = []

        sent = campaign_state.get("sent_count", 0)
        pending_followups = campaign_state.get("pending_followups", 0)

        if sent > 5 and pending_followups == 0:
            cards.append(GuidanceCard(
                type="no_followups",
                severity=GuidanceSeverity.INFO,
                message=(
                    f"You've sent {sent} emails but have no follow-ups scheduled. "
                    f"Follow-ups can increase response rates by 2-3x. Consider scheduling "
                    f"follow-ups for your top opportunities."
                ),
                action_text="Schedule Follow-ups",
            ))

        return cards[:self.MAX_ACTIVE_CARDS]

    def evaluate_campaign_health(self, stats: dict) -> list[GuidanceCard]:
        """Evaluate campaign health metrics."""
        cards = []

        sent = stats.get("sent", 0)
        bounced = stats.get("bounced", 0)

        if sent > 0:
            bounce_rate = bounced / sent
            if bounce_rate > 0.2:
                cards.append(GuidanceCard(
                    type="high_bounce_rate",
                    severity=GuidanceSeverity.CRITICAL if bounce_rate > 0.4 else GuidanceSeverity.WARNING,
                    message=(
                        f"Your bounce rate is {bounce_rate:.0%} ({bounced}/{sent}). "
                        f"This damages your sender reputation. Verify your contact "
                        f"emails before sending more. Consider using an email verification service."
                    ),
                    action_text="Verify Contacts",
                ))

        return cards[:self.MAX_ACTIVE_CARDS]

    def evaluate_all(self, contacts=None, drafts=None, campaign_state=None,
                     campaign_health=None, opportunities=None) -> list[GuidanceCard]:
        """Run all evaluations and return top guidance cards."""
        all_cards = []
        if contacts:
            all_cards.extend(self.evaluate_contacts(contacts))
        if opportunities:
            all_cards.extend(self.evaluate_opportunity_selection(opportunities))
        if drafts:
            all_cards.extend(self.evaluate_drafts(drafts))
        if campaign_state:
            all_cards.extend(self.evaluate_campaign(campaign_state))
        if campaign_health:
            all_cards.extend(self.evaluate_campaign_health(campaign_health))

        # Priority: critical > warning > info
        priority = {GuidanceSeverity.CRITICAL: 0, GuidanceSeverity.WARNING: 1, GuidanceSeverity.INFO: 2}
        all_cards.sort(key=lambda c: priority.get(c.severity, 2))

        return all_cards[:self.MAX_ACTIVE_CARDS]
