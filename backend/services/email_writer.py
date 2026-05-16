"""
JobBus Backend — Email Writer.

Angle-first email generation using the Hook-Context-Credibility-CTA pattern.
Ported from the Swift EmailWriter but redesigned around angles.

Supports all AI providers (Gemini, Groq, OpenAI) via httpx REST — no SDK imports.
"""

from __future__ import annotations


import json
import re
import random
import httpx
from typing import Optional

from models.schemas import EmailDraft, AngleResult
from models.enums import AngleType


# ─── Provider REST endpoints ───────────────────────────────────────────────

_PROVIDER_CONFIGS = {
    "gemini": {
        "base_url": "https://generativelanguage.googleapis.com/v1beta/models",
        "model": "gemini-2.0-flash",
    },
    "groq": {
        "base_url": "https://api.groq.com/openai/v1",
        "model": "llama-3.3-70b-versatile",
    },
    "openai": {
        "base_url": "https://api.openai.com/v1",
        "model": "gpt-4o-mini",
    },
}


async def _call_ai(provider: str, api_key: str, prompt: str) -> str:
    """Call any AI provider and return the raw text response.

    Supports: gemini, groq, openai.
    Raises ValueError with a descriptive message on failure.
    """
    cfg = _PROVIDER_CONFIGS.get(provider, _PROVIDER_CONFIGS["gemini"])

    async with httpx.AsyncClient(timeout=60.0) as client:
        if provider == "gemini":
            resp = await client.post(
                f"{cfg['base_url']}/{cfg['model']}:generateContent",
                params={"key": api_key},
                json={
                    "contents": [{"parts": [{"text": prompt}]}],
                    "generationConfig": {"temperature": 0.7, "maxOutputTokens": 1024},
                },
            )
        else:
            # OpenAI-compatible (Groq + OpenAI)
            resp = await client.post(
                f"{cfg['base_url']}/chat/completions",
                headers={"Authorization": f"Bearer {api_key}"},
                json={
                    "model": cfg["model"],
                    "messages": [{"role": "user", "content": prompt}],
                    "temperature": 0.7,
                },
            )

    if not resp.is_success:
        raise ValueError(
            f"{provider.title()} API error {resp.status_code}: "
            f"{resp.text[:200]}"
        )

    data = resp.json()
    if provider == "gemini":
        candidates = data.get("candidates", [])
        if not candidates:
            raise ValueError("Gemini returned no candidates")
        return candidates[0]["content"]["parts"][0]["text"]
    else:
        return data["choices"][0]["message"]["content"]


class EmailWriter:
    """Generates personalized outreach emails using the angle-first approach.

    Supports any AI provider (gemini, groq, openai) — no SDK dependency.
    """

    SYSTEM_PROMPT = """You are an expert career outreach email writer. You write short, human, contextual emails.

MANDATORY STRUCTURE:
1. Hook — A specific observation about the recipient or their company. NO generic openings.
2. Context — Why this outreach makes sense (1-2 sentences max).
3. Credibility — ONE relevant achievement (quantified if possible). NOT a resume dump.
4. CTA — A light, natural ask (question, not demand).

STRICT RULES:
- Under 150 words total
- NO "I came across your profile"
- NO "I hope this finds you well"
- NO "I am writing to express"
- NO "Dear Hiring Manager"
- NO resume dumps (only ONE achievement)
- Subject line: specific, under 60 chars, NO "Job Application" or "Resume"
- Use the recipient's first name
- Sound human, not AI-generated
- End with a question, not a statement

Return ONLY valid JSON:
{"subject": "...", "body": "..."}"""

    def __init__(self, api_key: str, provider: str = "gemini"):
        """Initialize with a provider key and name.

        Args:
            api_key: Decrypted API key for the provider.
            provider: One of "gemini" (default), "groq", "openai".
        """
        self._api_key = api_key
        self._provider = provider if provider in _PROVIDER_CONFIGS else "gemini"

    async def generate(
        self,
        contact: dict,
        resume_profile: dict,
        angle: AngleResult | dict,
        previous_subjects: list[str] = None,
    ) -> EmailDraft:
        """Generate a single outreach email draft.

        Args:
            contact: {first_name, last_name, title, company, email}
            resume_profile: {name, role, skills, achievements, email_context}
            angle: Determined outreach angle with hook guidance
            previous_subjects: Subjects from earlier drafts (for diversity)
        """
        if isinstance(angle, dict):
            angle_type = angle.get("angle_type", "curiosity_based")
            hook_guidance = angle.get("hook_guidance", "")
            reasoning = angle.get("reasoning", "")
            signals_used = angle.get("signals_used", [])
        else:
            angle_type = angle.angle_type
            hook_guidance = angle.hook_guidance
            reasoning = angle.reasoning
            signals_used = angle.signals_used

        # Pick a random achievement (for diversity)
        achievements = resume_profile.get("achievements", [])
        selected_achievement = random.choice(achievements) if achievements else ""

        avoid_line = (
            f"AVOID these subject lines (already used): {', '.join(previous_subjects[:5])}"
            if previous_subjects else ""
        )

        prompt = f"""{self.SYSTEM_PROMPT}

OUTREACH ANGLE: {angle_type}
HOOK GUIDANCE: {hook_guidance}

RECIPIENT:
- Name: {contact.get('first_name', '')} {contact.get('last_name', '')}
- Title: {contact.get('title', '')}
- Company: {contact.get('company', '')}

CANDIDATE:
- Name: {resume_profile.get('name', '')}
- Background: {resume_profile.get('email_context', '')}
- Achievement to use: {selected_achievement}

{avoid_line}

Generate the email now. Return ONLY JSON."""

        raw = await _call_ai(self._provider, self._api_key, prompt)
        raw = raw.strip()

        # Extract JSON
        json_match = re.search(r"\{.*\}", raw, re.DOTALL)
        if json_match:
            raw = json_match.group(0)

        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            data = {
                "subject": f"Quick question for {contact.get('first_name', 'you')}",
                "body": raw,
            }

        # Normalize signals_used to list[dict] (schema requires dict, not str)
        if signals_used and isinstance(signals_used[0], str):
            signals_used = [{"signal": s} for s in signals_used]

        return EmailDraft(
            contact_id=contact.get("id", ""),
            subject=data.get("subject", ""),
            body=data.get("body", ""),
            angle_type=AngleType(angle_type) if isinstance(angle_type, str) else angle_type,
            angle_reasoning=reasoning,
            signals_used=signals_used or [],
        )

    async def generate_batch(
        self,
        contacts: list[dict],
        resume_profile: dict,
        angle: AngleResult | dict,
    ) -> list[EmailDraft]:
        """Generate drafts for multiple contacts with diversity."""
        drafts = []
        used_subjects: list[str] = []

        for contact in contacts:
            draft = await self.generate(
                contact, resume_profile, angle, previous_subjects=used_subjects
            )
            used_subjects.append(draft.subject)
            drafts.append(draft)

        return drafts
