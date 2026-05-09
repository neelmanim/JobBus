"""
JobBus Backend — SMTP Sender.

Server-side email relay. User SMTP credentials are decrypted at send time
and never exposed to the frontend.
"""

from __future__ import annotations


import smtplib
import time
import random
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime, timezone
from typing import Optional
from dataclasses import dataclass

from services.credential_service import get_credential_service, CredentialNotFound
from config import get_settings


@dataclass
class SendResult:
    success: bool
    message_id: Optional[str] = None
    error_type: Optional[str] = None
    error_message: Optional[str] = None


class SMTPSender:
    """Sends emails via the user's SMTP credentials (server-side relay)."""

    def __init__(self, max_per_hour: int = None):
        settings = get_settings()
        self.max_per_hour = max_per_hour or settings.max_emails_per_hour
        self._send_timestamps: dict[str, list[datetime]] = {}

    async def send(
        self,
        user_id: str,
        to_email: str,
        subject: str,
        body: str,
        reply_to: Optional[str] = None,
    ) -> SendResult:
        """Send a single email via the user's SMTP credentials."""
        # Rate limit check
        if self._is_rate_limited(user_id):
            return SendResult(
                success=False,
                error_type="rate_limited",
                error_message=f"Rate limit exceeded ({self.max_per_hour}/hour). Please wait.",
            )

        # Get decrypted credentials
        try:
            cred_service = get_credential_service()
            creds = cred_service.get_decrypted(user_id)
        except CredentialNotFound:
            return SendResult(
                success=False,
                error_type="no_credentials",
                error_message="No SMTP credentials configured. Please set up email in Settings.",
            )
        except Exception as e:
            return SendResult(
                success=False,
                error_type="credential_error",
                error_message=str(e),
            )

        # Build email
        msg = MIMEMultipart("alternative")
        msg["From"] = f"{creds.get('sender_name', '')} <{creds['smtp_user']}>"
        msg["To"] = to_email
        msg["Subject"] = subject
        if reply_to:
            msg["Reply-To"] = reply_to

        # Plain text body
        msg.attach(MIMEText(body, "plain", "utf-8"))

        # Send via SMTP
        try:
            with smtplib.SMTP(creds["smtp_host"], creds["smtp_port"], timeout=30) as server:
                server.starttls()
                server.login(creds["smtp_user"], creds["smtp_pass"])
                result = server.send_message(msg)

            self._record_send(user_id)

            return SendResult(
                success=True,
                message_id=msg.get("Message-ID", ""),
            )

        except smtplib.SMTPAuthenticationError:
            return SendResult(
                success=False,
                error_type="auth_error",
                error_message="SMTP authentication failed. Check your app password.",
            )
        except smtplib.SMTPRecipientsRefused:
            return SendResult(
                success=False,
                error_type="bounce",
                error_message=f"Recipient rejected: {to_email}",
            )
        except smtplib.SMTPException as e:
            return SendResult(
                success=False,
                error_type="smtp_error",
                error_message=str(e),
            )
        except Exception as e:
            return SendResult(
                success=False,
                error_type="unknown",
                error_message=str(e),
            )

    def _is_rate_limited(self, user_id: str) -> bool:
        """Check if user has exceeded per-hour rate limit."""
        now = datetime.now(timezone.utc)
        timestamps = self._send_timestamps.get(user_id, [])
        # Keep only last hour
        cutoff = now.timestamp() - 3600
        timestamps = [t for t in timestamps if t.timestamp() > cutoff]
        self._send_timestamps[user_id] = timestamps
        return len(timestamps) >= self.max_per_hour

    def _record_send(self, user_id: str) -> None:
        """Record a send timestamp for rate limiting."""
        if user_id not in self._send_timestamps:
            self._send_timestamps[user_id] = []
        self._send_timestamps[user_id].append(datetime.now(timezone.utc))

    def get_next_delays(self, batch_size: int) -> list[int]:
        """Generate adaptive delays between sends (30-90 seconds, varied)."""
        return [random.randint(30, 90) for _ in range(batch_size)]


# Singleton
_smtp_sender: SMTPSender | None = None


def get_smtp_sender() -> SMTPSender:
    global _smtp_sender
    if _smtp_sender is None:
        _smtp_sender = SMTPSender()
    return _smtp_sender
