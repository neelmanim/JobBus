"""
JobBus — AI Provider Base Protocol.

All AI providers implement AIProvider.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol, runtime_checkable


# ─────────────────────────────────────────────────────────────
# Data Model
# ─────────────────────────────────────────────────────────────

@dataclass
class GenerationResult:
    """Normalized output from any AI provider."""

    text: str
    model: str
    provider: str
    tokens_used: int = 0
    latency_ms: float = 0.0


# ─────────────────────────────────────────────────────────────
# Protocol
# ─────────────────────────────────────────────────────────────

@runtime_checkable
class AIProvider(Protocol):
    """Protocol all AI providers must implement."""

    provider_name: str   # "groq" | "gemini" | "openai" | "ollama"
    model: str           # actual model identifier

    async def generate(
        self,
        system_prompt: str,
        user_prompt: str,
        temperature: float = 0.7,
        max_tokens: int = 1024,
    ) -> GenerationResult:
        """
        Generate text from a prompt pair.

        Args:
            system_prompt: The system / persona instruction
            user_prompt:   The actual task / user message
            temperature:   0.0 (deterministic) → 1.0 (creative)
            max_tokens:    Maximum tokens to generate

        Returns:
            GenerationResult with text and metadata
        """
        ...

    async def test_connection(self) -> bool:
        """Verify the API key and model are accessible. Returns True on success."""
        ...
