"""
JobBus — OpenAI AI Provider.

Supports GPT-4o mini (fast, cheap) and GPT-4o (max quality).
"""

from __future__ import annotations

import time
import logging
import httpx

from providers.ai.base import GenerationResult

logger = logging.getLogger(__name__)

_BASE_URL = "https://api.openai.com/v1"

MODELS = {
    "auto": "gpt-4o-mini",
    "fast": "gpt-4o-mini",
    "quality": "gpt-4o",
}


class OpenAIProvider:
    """OpenAI AI provider."""

    provider_name = "openai"

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

        async with httpx.AsyncClient(timeout=60.0) as client:
            try:
                resp = await client.post(
                    f"{_BASE_URL}/chat/completions",
                    json={
                        "model": self.model,
                        "messages": [
                            {"role": "system", "content": system_prompt},
                            {"role": "user", "content": user_prompt},
                        ],
                        "temperature": temperature,
                        "max_tokens": max_tokens,
                    },
                    headers={
                        "Authorization": f"Bearer {self._api_key}",
                        "Content-Type": "application/json",
                    },
                )
                resp.raise_for_status()
            except httpx.HTTPStatusError as e:
                if e.response.status_code == 401:
                    raise ValueError("OpenAI: Invalid API key")
                if e.response.status_code == 429:
                    raise ValueError("OpenAI: Rate limit / quota exceeded")
                raise ValueError(f"OpenAI API error: {e.response.status_code}")

        data = resp.json()
        text = data["choices"][0]["message"]["content"]
        tokens = data.get("usage", {}).get("total_tokens", 0)

        return GenerationResult(
            text=text,
            model=self.model,
            provider="openai",
            tokens_used=tokens,
            latency_ms=(time.monotonic() - start) * 1000,
        )

    async def test_connection(self) -> bool:
        try:
            result = await self.generate("You are a test.", "Reply: OK", max_tokens=5)
            return bool(result.text)
        except Exception:
            return False
