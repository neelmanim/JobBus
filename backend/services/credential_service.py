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


# Singleton
_credential_service: CredentialService | None = None


def get_credential_service() -> CredentialService:
    """Get or create the credential service singleton."""
    global _credential_service
    if _credential_service is None:
        _credential_service = CredentialService()
    return _credential_service
