"""
JobBus — Gemini AI Provider.

Uses Google's Gemini 2.0 Flash (free tier, very generous).
Refactored from resume_analyzer.py to match AIProvider protocol.
"""

from __future__ import annotations

import time
import logging
import httpx

from providers.ai.base import GenerationResult

logger = logging.getLogger(__name__)

MODELS = {
    "auto": "gemini-2.0-flash",
    "fast": "gemini-2.0-flash",
    "quality": "gemini-2.0-flash-thinking-exp",
}

_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models"


class GeminiAIProvider:
    """Google Gemini AI provider."""

    provider_name = "gemini"

    def __init__(self, api_key: str, model: str = "auto") -> None:
        self._api_key = api_key
        self.model = MODELS.get(model, model)

    async def generate(
        self,
        system_prompt: str,
        user_prompt: str,
        temperature: float = 0.7,
        max_tokens: int = 1024,
    ) -> GenerationResult:
        start = time.monotonic()

        # Gemini combines system + user into a single prompt
        full_prompt = f"{system_prompt}\n\n{user_prompt}"

        async with httpx.AsyncClient(timeout=60.0) as client:
            try:
                resp = await client.post(
                    f"{_BASE_URL}/{self.model}:generateContent",
                    params={"key": self._api_key},
                    json={
                        "contents": [{"parts": [{"text": full_prompt}]}],
                        "generationConfig": {
                            "temperature": temperature,
                            "maxOutputTokens": max_tokens,
                        },
                    },
                )
                resp.raise_for_status()
            except httpx.HTTPStatusError as e:
                if e.response.status_code == 400:
                    raise ValueError("Gemini: Invalid API key or malformed request")
                if e.response.status_code == 429:
                    raise ValueError("Gemini: Quota exceeded")
                raise ValueError(f"Gemini API error: {e.response.status_code}")

        data = resp.json()
        candidates = data.get("candidates", [])
        if not candidates:
            raise ValueError("Gemini: No response generated")

        text = candidates[0]["content"]["parts"][0]["text"]
        tokens = data.get("usageMetadata", {}).get("totalTokenCount", 0)

        return GenerationResult(
            text=text,
            model=self.model,
            provider="gemini",
            tokens_used=tokens,
            latency_ms=(time.monotonic() - start) * 1000,
        )

    async def test_connection(self) -> bool:
        """Test Gemini API key by listing available models (no tokens consumed).

        Google returns 200 for a valid key and 400/403 for an invalid one.
        """
        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                resp = await client.get(
                    "https://generativelanguage.googleapis.com/v1beta/models",
                    params={"key": self._api_key},
                )
                # 200 = valid key; 400/403 = invalid or restricted key
                return resp.status_code == 200
            except Exception:
                return False
