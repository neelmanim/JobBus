"""
JobBus — Groq AI Provider.

Uses Groq's LPU hardware for fastest-in-class inference.
Default model: llama-3.1-8b-instant (~$0.05/M tokens, sub-second).
Quality model: llama-3.3-70b-versatile (~$0.59/M tokens).
"""

from __future__ import annotations

import time
import logging
import httpx

from providers.ai.base import GenerationResult

logger = logging.getLogger(__name__)

_BASE_URL = "https://api.groq.com/openai/v1"

MODELS = {
    "auto": "llama-3.1-8b-instant",
    "fast": "llama-3.1-8b-instant",
    "quality": "llama-3.3-70b-versatile",
}


class GroqAIProvider:
    """Groq AI provider using OpenAI-compatible API."""

    provider_name = "groq"

    def __init__(self, api_key: str, model: str = "auto") -> None:
        self._api_key = api_key
        self.model = MODELS.get(model, model)  # allow raw model IDs

    async def generate(
        self,
        system_prompt: str,
        user_prompt: str,
        temperature: float = 0.7,
        max_tokens: int = 1024,
    ) -> GenerationResult:
        """Generate text using Groq."""
        start = time.monotonic()

        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "temperature": temperature,
            "max_tokens": max_tokens,
        }

        async with httpx.AsyncClient(timeout=30.0) as client:
            try:
                resp = await client.post(
                    f"{_BASE_URL}/chat/completions",
                    json=payload,
                    headers={
                        "Authorization": f"Bearer {self._api_key}",
                        "Content-Type": "application/json",
                    },
                )
                resp.raise_for_status()
            except httpx.HTTPStatusError as e:
                if e.response.status_code == 401:
                    raise ValueError("Groq: Invalid API key")
                if e.response.status_code == 429:
                    raise ValueError("Groq: Rate limit exceeded — try again shortly")
                raise ValueError(f"Groq API error: {e.response.status_code}")

        data = resp.json()
        text = data["choices"][0]["message"]["content"]
        tokens = data.get("usage", {}).get("total_tokens", 0)
        latency = (time.monotonic() - start) * 1000

        return GenerationResult(
            text=text,
            model=self.model,
            provider="groq",
            tokens_used=tokens,
            latency_ms=latency,
        )

    async def test_connection(self) -> bool:
        """Test Groq API key."""
        try:
            result = await self.generate(
                system_prompt="You are a test assistant.",
                user_prompt="Reply with exactly: OK",
                max_tokens=5,
            )
            return bool(result.text)
        except Exception:
            return False
