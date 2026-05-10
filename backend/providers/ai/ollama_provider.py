"""
JobBus — Ollama AI Provider.

Runs locally — zero cost, zero data leaves the machine.
Default base URL: http://localhost:11434.
"""

from __future__ import annotations

import time
import logging
import httpx

from providers.ai.base import GenerationResult

logger = logging.getLogger(__name__)


class OllamaProvider:
    """Ollama local AI provider."""

    provider_name = "ollama"

    def __init__(self, base_url: str = "http://localhost:11434", model: str = "llama3.1:8b") -> None:
        self.base_url = base_url.rstrip("/")
        self.model = model

    async def generate(
        self,
        system_prompt: str,
        user_prompt: str,
        temperature: float = 0.7,
        max_tokens: int = 1024,
    ) -> GenerationResult:
        start = time.monotonic()

        async with httpx.AsyncClient(timeout=120.0) as client:  # Local can be slow
            try:
                resp = await client.post(
                    f"{self.base_url}/api/chat",
                    json={
                        "model": self.model,
                        "messages": [
                            {"role": "system", "content": system_prompt},
                            {"role": "user", "content": user_prompt},
                        ],
                        "stream": False,
                        "options": {
                            "temperature": temperature,
                            "num_predict": max_tokens,
                        },
                    },
                )
                resp.raise_for_status()
            except httpx.ConnectError:
                raise ValueError(
                    f"Ollama: Cannot connect to {self.base_url}. "
                    "Is Ollama running? Run: ollama serve"
                )
            except httpx.HTTPStatusError as e:
                raise ValueError(f"Ollama error: {e.response.status_code}")

        data = resp.json()
        text = data.get("message", {}).get("content", "")
        tokens = data.get("eval_count", 0) + data.get("prompt_eval_count", 0)

        return GenerationResult(
            text=text,
            model=self.model,
            provider="ollama",
            tokens_used=tokens,
            latency_ms=(time.monotonic() - start) * 1000,
        )

    async def test_connection(self) -> bool:
        """Check if Ollama is running and the model is available."""
        async with httpx.AsyncClient(timeout=5.0) as client:
            try:
                resp = await client.get(f"{self.base_url}/api/tags")
                if resp.status_code != 200:
                    return False
                models = [m["name"] for m in resp.json().get("models", [])]
                return any(self.model in m for m in models)
            except Exception:
                return False
