"""
JobBus Backend — Credential Service.

Encrypts/decrypts SMTP credentials using Fernet symmetric encryption.
User credentials are NEVER stored in plaintext.
"""

from __future__ import annotations


from cryptography.fernet import Fernet, InvalidToken
from config import get_settings
from database import get_supabase_admin
from models.schemas import SMTPCredentialCreate, SMTPCredentialStatus


class DecryptionError(Exception):
    """Raised when credentials can't be decrypted."""
    pass


class CredentialNotFound(Exception):
    """Raised when no credentials found for user."""
    pass


class CredentialService:
    """Manages encrypted SMTP credential storage."""

    def __init__(self, encryption_key: str | None = None):
        key = encryption_key or get_settings().encryption_key
        if not key:
            raise ValueError(
                "Encryption key not configured. Generate one with: "
                "python -c \"from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())\""
            )
        self._fernet = Fernet(key.encode() if isinstance(key, str) else key)

    def _encrypt(self, plaintext: str) -> str:
        """Encrypt a string."""
        return self._fernet.encrypt(plaintext.encode()).decode()

    def _decrypt(self, ciphertext: str) -> str:
        """Decrypt a string."""
        try:
            return self._fernet.decrypt(ciphertext.encode()).decode()
        except InvalidToken:
            raise DecryptionError("Failed to decrypt credentials. Encryption key may have changed.")

    def store(self, user_id: str, credentials: SMTPCredentialCreate) -> None:
        """Store encrypted SMTP credentials for a user."""
        supabase = get_supabase_admin()

        encrypted_data = {
            "user_id": user_id,
            "smtp_host": credentials.smtp_host,
            "smtp_port": credentials.smtp_port,
            "smtp_user": credentials.smtp_user,
            "smtp_pass_encrypted": self._encrypt(credentials.smtp_pass),
            "sender_name": credentials.sender_name or credentials.smtp_user.split("@")[0],
        }

        # Upsert — replace if exists
        existing = supabase.table("smtp_credentials").select("id").eq("user_id", user_id).execute()
        if existing.data:
            supabase.table("smtp_credentials").update(
                encrypted_data
            ).eq("user_id", user_id).execute()
        else:
            supabase.table("smtp_credentials").insert(encrypted_data).execute()

    def get_decrypted(self, user_id: str) -> dict:
        """Get decrypted SMTP credentials for sending."""
        supabase = get_supabase_admin()
        result = supabase.table("smtp_credentials").select("*").eq("user_id", user_id).execute()

        if not result.data:
            raise CredentialNotFound(f"No SMTP credentials found for user {user_id}")

        row = result.data[0]
        return {
            "smtp_host": row["smtp_host"],
            "smtp_port": row["smtp_port"],
            "smtp_user": row["smtp_user"],
            "smtp_pass": self._decrypt(row["smtp_pass_encrypted"]),
            "sender_name": row.get("sender_name", ""),
        }

    def get_status(self, user_id: str) -> SMTPCredentialStatus:
        """Get credential status (no secrets exposed)."""
        supabase = get_supabase_admin()
        result = supabase.table("smtp_credentials").select(
            "smtp_host, smtp_user, sender_name"
        ).eq("user_id", user_id).execute()

        if not result.data:
            return SMTPCredentialStatus(configured=False)

        row = result.data[0]
        return SMTPCredentialStatus(
            configured=True,
            smtp_host=row["smtp_host"],
            smtp_user=row["smtp_user"],
            sender_name=row.get("sender_name"),
        )

    def delete(self, user_id: str) -> None:
        """Delete stored credentials for a user."""
        supabase = get_supabase_admin()
        supabase.table("smtp_credentials").delete().eq("user_id", user_id).execute()

    # ─── Multi-provider key management ────────────────────────────

    # Map of logical field name → DB column name in user_secrets
    _PROVIDER_FIELDS = {
        "groq_key": "groq_key_encrypted",
        "openai_key": "openai_key_encrypted",
        "gemini_key": "gemini_key_encrypted",
        "hunter_key": "hunter_key_encrypted",
        "apollo_key": "apollo_key_encrypted",
        "rocketreach_key": "rocketreach_key_encrypted",
        "ollama_base_url": "ollama_base_url",  # not encrypted
    }

    _UNENCRYPTED_FIELDS = {"ollama_base_url"}

    def store_provider_key(self, user_id: str, field: str, value: str) -> None:
        """Encrypt and store a single provider key."""
        col = self._PROVIDER_FIELDS.get(field)
        if not col:
            raise ValueError(f"Unknown provider field: {field}")

        encrypted = value if field in self._UNENCRYPTED_FIELDS else self._encrypt(value)

        supabase = get_supabase_admin()
        existing = supabase.table("user_secrets").select("id").eq("user_id", user_id).execute()

        if existing.data:
            supabase.table("user_secrets").update(
                {col: encrypted, "updated_at": "NOW()"}
            ).eq("user_id", user_id).execute()
        else:
            supabase.table("user_secrets").insert(
                {"user_id": user_id, col: encrypted}
            ).execute()

    def get_decrypted_field(self, user_id: str, field: str) -> str | None:
        """Retrieve and decrypt a single provider key. Returns None if not set."""
        col = self._PROVIDER_FIELDS.get(field)
        if not col:
            raise ValueError(f"Unknown provider field: {field}")

        supabase = get_supabase_admin()
        result = supabase.table("user_secrets").select(col).eq("user_id", user_id).execute()

        if not result.data:
            return None

        raw = result.data[0].get(col)
        if not raw:
            return None

        if field in self._UNENCRYPTED_FIELDS:
            return raw
        return self._decrypt(raw)

    def get_provider_status(self, user_id: str) -> dict:
        """Return which provider keys are configured (booleans, no secrets exposed)."""
        supabase = get_supabase_admin()
        result = supabase.table("user_secrets").select("*").eq("user_id", user_id).execute()

        row = result.data[0] if result.data else {}
        return {
            "groq": bool(row.get("groq_key_encrypted")),
            "openai": bool(row.get("openai_key_encrypted")),
            "gemini": bool(row.get("gemini_key_encrypted")),
            "hunter": bool(row.get("hunter_key_encrypted")),
            "apollo": bool(row.get("apollo_key_encrypted")),
            "rocketreach": bool(row.get("rocketreach_key_encrypted")),
            "ollama_url": row.get("ollama_base_url") or None,
        }


# Singleton
_credential_service: CredentialService | None = None


def get_credential_service() -> CredentialService:
    """Get or create the credential service singleton."""
    global _credential_service
    if _credential_service is None:
        _credential_service = CredentialService()
    return _credential_service
