"""
JobBus Backend — Quality Scorer.

11-point validation + 3 new v2 checks for email quality.
Ported from Swift QualityScorer and enhanced.
"""

from __future__ import annotations


import re
from models.schemas import QualityCheckResult, QualityScoreResult


SPAM_WORDS = {
    "urgent", "act now", "limited time", "congratulations", "winner",
    "free money", "click here", "unsubscribe", "opt-out", "100% free",
    "guaranteed", "no obligation", "risk-free", "special offer",
    "amazing deal", "once in a lifetime",
}

BANNED_PHRASES = [
    "i came across your profile",
    "i hope this finds you well",
    "i hope this email finds you",
    "i am writing to express",
    "i wanted to reach out",
    "dear hiring manager",
    "to whom it may concern",
    "i am a passionate",
    "i am excited to",
    "please find attached my resume",
    "i would like to apply",
]

GENERIC_OPENERS = [
    "i came across",
    "i noticed your",
    "i wanted to reach out",
    "i recently discovered",
    "i saw your profile",
    "i hope you're doing well",
]


class QualityScorer:
    """Validates email quality using 14 checks (11 original + 3 new)."""

    def score(self, email: dict) -> QualityScoreResult:
        """Score an email draft on quality. Returns 0-10 scale."""
        subject = email.get("subject", "")
        body = email.get("body", "")
        recipient_name = email.get("recipient_name", "")
        recipient_company = email.get("recipient_company", "")

        checks = [
            self._check_subject_length(subject),
            self._check_body_length(body),
            self._check_spam_words(subject + " " + body),
            self._check_cta(body),
            self._check_personalization(body, recipient_name, recipient_company),
            self._check_professional_tone(body),
            self._check_excessive_caps(body),
            self._check_excessive_exclamation(body),
            self._check_link_count(body),
            self._check_signature(body),
            self._check_grammar_basics(body),
            # V2 checks
            self._check_banned_phrases(body),
            self._check_opening_diversity(body),
            self._check_achievement_count(body, email.get("achievements", [])),
        ]

        passed = sum(1 for c in checks if c.passed)
        total = round(passed / len(checks) * 10, 1)

        return QualityScoreResult(total=total, checks=checks)

    # ── Original 11 Checks ──────────────────────────────────

    @staticmethod
    def _check_subject_length(subject: str) -> QualityCheckResult:
        length = len(subject)
        passed = 5 <= length <= 78
        return QualityCheckResult(
            name="subject_length",
            passed=passed,
            detail=f"Subject is {length} chars (5-78 required)",
        )

    @staticmethod
    def check_subject_length(subject: str) -> bool:
        return 5 <= len(subject) <= 78

    @staticmethod
    def _check_body_length(body: str) -> QualityCheckResult:
        words = len(body.split())
        passed = 30 <= words <= 300
        return QualityCheckResult(
            name="body_length",
            passed=passed,
            detail=f"Body is {words} words (30-300 required)",
        )

    @staticmethod
    def _check_spam_words(text: str) -> QualityCheckResult:
        text_lower = text.lower()
        found = [w for w in SPAM_WORDS if w in text_lower]
        passed = len(found) == 0
        return QualityCheckResult(
            name="spam_words",
            passed=passed,
            detail=f"Found spam words: {', '.join(found)}" if found else "No spam words detected",
        )

    @staticmethod
    def has_spam_words(text: str) -> bool:
        text_lower = text.lower()
        return any(w in text_lower for w in SPAM_WORDS)

    @staticmethod
    def _check_cta(body: str) -> QualityCheckResult:
        cta_patterns = ["?", "would you", "open to", "interested in", "thoughts on",
                        "chat", "connect", "call", "coffee", "meet"]
        body_lower = body.lower()
        has = any(p in body_lower for p in cta_patterns)
        return QualityCheckResult(
            name="cta_presence",
            passed=has,
            detail="CTA found" if has else "No call-to-action detected",
        )

    @staticmethod
    def has_cta(text: str) -> bool:
        patterns = ["?", "would you", "open to", "chat", "connect", "call", "thoughts"]
        return any(p in text.lower() for p in patterns)

    @staticmethod
    def _check_personalization(body: str, name: str, company: str) -> QualityCheckResult:
        body_lower = body.lower()
        has_name = name.lower() in body_lower if name else False
        has_company = company.lower() in body_lower if company else False
        passed = has_name or has_company
        return QualityCheckResult(
            name="personalization",
            passed=passed,
            detail=f"Name: {'✓' if has_name else '✗'}, Company: {'✓' if has_company else '✗'}",
        )

    @staticmethod
    def is_personalized(body: str, name: str, company: str) -> bool:
        body_lower = body.lower()
        return (name.lower() in body_lower) or (company.lower() in body_lower)

    @staticmethod
    def _check_professional_tone(body: str) -> QualityCheckResult:
        informal = ["lol", "omg", "btw", "lmao", "ngl", "tbh", "imo"]
        body_lower = body.lower()
        found = [w for w in informal if f" {w} " in f" {body_lower} "]
        passed = len(found) == 0
        return QualityCheckResult(
            name="professional_tone",
            passed=passed,
            detail=f"Informal words found: {', '.join(found)}" if found else "Professional tone",
        )

    @staticmethod
    def _check_excessive_caps(body: str) -> QualityCheckResult:
        words = body.split()
        if not words:
            return QualityCheckResult(name="excessive_caps", passed=True, detail="No text")
        caps_words = [w for w in words if w.isupper() and len(w) > 2]
        ratio = len(caps_words) / len(words)
        passed = ratio < 0.15
        return QualityCheckResult(
            name="excessive_caps",
            passed=passed,
            detail=f"{len(caps_words)}/{len(words)} words in ALL CAPS ({ratio:.0%})",
        )

    @staticmethod
    def _check_excessive_exclamation(body: str) -> QualityCheckResult:
        count = body.count("!")
        passed = count <= 2
        return QualityCheckResult(
            name="excessive_exclamation",
            passed=passed,
            detail=f"{count} exclamation marks (max 2)",
        )

    @staticmethod
    def _check_link_count(body: str) -> QualityCheckResult:
        links = re.findall(r"https?://\S+", body)
        passed = len(links) <= 2
        return QualityCheckResult(
            name="link_count",
            passed=passed,
            detail=f"{len(links)} links (max 2)",
        )

    @staticmethod
    def _check_signature(body: str) -> QualityCheckResult:
        sig_patterns = ["best,", "regards,", "cheers,", "thanks,", "thank you,", "sincerely,"]
        body_lower = body.lower().strip()
        has = any(body_lower.endswith(p) or p in body_lower[-100:] for p in sig_patterns)
        return QualityCheckResult(
            name="signature",
            passed=has,
            detail="Sign-off found" if has else "No sign-off detected",
        )

    @staticmethod
    def _check_grammar_basics(body: str) -> QualityCheckResult:
        issues = []
        if "  " in body:
            issues.append("double spaces")
        if body != body.strip():
            issues.append("leading/trailing whitespace")
        sentences = re.split(r'[.!?]\s+', body)
        uncapitalized = [s for s in sentences if s and s[0].islower() and not s.startswith("http")]
        if len(uncapitalized) > 1:
            issues.append(f"{len(uncapitalized)} uncapitalized sentences")
        passed = len(issues) == 0
        return QualityCheckResult(
            name="grammar_basics",
            passed=passed,
            detail=f"Issues: {', '.join(issues)}" if issues else "Grammar OK",
        )

    # ── V2 Checks ───────────────────────────────────────────

    @staticmethod
    def _check_banned_phrases(body: str) -> QualityCheckResult:
        body_lower = body.lower()
        found = [p for p in BANNED_PHRASES if p in body_lower]
        passed = len(found) == 0
        return QualityCheckResult(
            name="banned_phrases",
            passed=passed,
            detail=f"Banned phrases found: {found[0]}" if found else "No banned phrases",
        )

    @staticmethod
    def has_banned_phrases(text: str) -> bool:
        text_lower = text.lower()
        return any(p in text_lower for p in BANNED_PHRASES)

    @staticmethod
    def _check_opening_diversity(body: str) -> QualityCheckResult:
        first_line = body.strip().split("\n")[0].lower() if body else ""
        # Skip greeting line (e.g., "Hi Jane,")
        lines = [l.strip().lower() for l in body.strip().split("\n") if l.strip()]
        opening = lines[1] if len(lines) > 1 else lines[0] if lines else ""

        is_generic = any(opener in opening for opener in GENERIC_OPENERS)
        return QualityCheckResult(
            name="opening_diversity",
            passed=not is_generic,
            detail=f"Generic opening detected: '{opening[:50]}'" if is_generic else "Opening is contextual",
        )

    @staticmethod
    def is_generic_opening(text: str) -> bool:
        text_lower = text.lower().strip()
        return any(opener in text_lower for opener in GENERIC_OPENERS)

    @staticmethod
    def _check_achievement_count(body: str, achievements: list[str]) -> QualityCheckResult:
        if not achievements:
            return QualityCheckResult(name="achievement_count", passed=True, detail="No achievements to check")
        count = sum(1 for a in achievements if a.lower()[:20] in body.lower())
        passed = count <= 1
        return QualityCheckResult(
            name="achievement_count",
            passed=passed,
            detail=f"{count} achievements referenced (max 1)",
        )

    @staticmethod
    def check_achievement_count(body: str, achievements: list[str]) -> int:
        return sum(1 for a in achievements if a.lower()[:20] in body.lower())
