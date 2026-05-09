"""
JobBus Backend — Email Writer.

Angle-first email generation using the Hook-Context-Credibility-CTA pattern.
Ported from the Swift EmailWriter but redesigned around angles.
"""

from __future__ import annotations


import json
import re
import random
from typing import Optional

import google.generativeai as genai

from models.schemas import EmailDraft, AngleResult
from models.enums import AngleType


class EmailWriter:
    """Generates personalized outreach emails using the angle-first approach."""

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

    def __init__(self, api_key: str):
        genai.configure(api_key=api_key)
        self.model = genai.GenerativeModel("gemini-2.0-flash")

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

{"AVOID these subject lines (already used): " + ', '.join(previous_subjects[:5]) if previous_subjects else ""}

Generate the email now. Return ONLY JSON."""

        response = self.model.generate_content(prompt)
        raw = response.text.strip()

        # Extract JSON
        json_match = re.search(r"\{.*\}", raw, re.DOTALL)
        if json_match:
            raw = json_match.group(0)

        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            data = {"subject": f"Quick question for {contact.get('first_name', 'you')}", "body": raw}

        return EmailDraft(
            contact_id=contact.get("id", ""),
            subject=data.get("subject", ""),
            body=data.get("body", ""),
            angle_type=AngleType(angle_type) if isinstance(angle_type, str) else angle_type,
            angle_reasoning=reasoning,
            signals_used=signals_used,
        )

    async def generate_batch(
        self,
        contacts: list[dict],
        resume_profile: dict,
        angle: AngleResult | dict,
    ) -> list[EmailDraft]:
        """Generate drafts for multiple contacts with diversity."""
        drafts = []
        used_subjects = []

        for contact in contacts:
            draft = await self.generate(contact, resume_profile, angle, previous_subjects=used_subjects)
            used_subjects.append(draft.subject)
            drafts.append(draft)

        return drafts
