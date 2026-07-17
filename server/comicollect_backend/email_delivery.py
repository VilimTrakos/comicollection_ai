"""Provider-neutral email delivery contract and a TLS-only SMTP adapter."""

from __future__ import annotations

import re
import smtplib
import ssl
from dataclasses import dataclass
from email.headerregistry import Address
from email.message import EmailMessage
from email.policy import SMTP
from typing import Callable, Protocol, runtime_checkable

from .config import EmailDeliveryConfig


_MESSAGE_ID = re.compile(r"^<[A-Za-z0-9._+-]{1,128}@[A-Za-z0-9.-]{1,253}>$")
_MAX_SUBJECT_CHARACTERS = 200
_MAX_BODY_BYTES = 512 * 1024


@dataclass(frozen=True)
class OutboundEmail:
    """One already-rendered message; raw action tokens live only in memory."""

    message_id: str
    recipient: str
    subject: str
    text_body: str
    html_body: str | None = None


@dataclass(frozen=True)
class DeliveryReceipt:
    """Transport acknowledgement without provider-specific response details."""

    provider_message_id: str | None = None


class EmailDeliveryError(RuntimeError):
    """A sanitized delivery failure safe for metrics and bounded retry logic."""

    def __init__(self, code: str, *, retryable: bool):
        super().__init__("Email delivery failed")
        self.code = code
        self.retryable = retryable


@runtime_checkable
class EmailSender(Protocol):
    def send(self, message: OutboundEmail) -> DeliveryReceipt:
        """Deliver one message or raise :class:`EmailDeliveryError`."""


class _SmtpConnection(Protocol):
    def ehlo(self): ...

    def starttls(self, *, context: ssl.SSLContext): ...

    def login(self, user: str, password: str): ...

    def send_message(
        self,
        msg: EmailMessage,
        from_addr: str,
        to_addrs: list[str],
    ) -> dict: ...

    def quit(self): ...

    def close(self): ...


SmtpFactory = Callable[..., _SmtpConnection]
SslContextFactory = Callable[[], ssl.SSLContext]


class SmtpEmailSender:
    """Deliver rendered messages over authenticated or relay SMTP with TLS."""

    def __init__(
        self,
        config: EmailDeliveryConfig,
        *,
        smtp_factory: SmtpFactory = smtplib.SMTP,
        smtp_ssl_factory: SmtpFactory = smtplib.SMTP_SSL,
        ssl_context_factory: SslContextFactory = ssl.create_default_context,
    ):
        if config.transport != "smtp":
            raise ValueError("SMTP sender requires the smtp email transport")
        self.config = config
        self._smtp_factory = smtp_factory
        self._smtp_ssl_factory = smtp_ssl_factory
        self._ssl_context_factory = ssl_context_factory

    def send(self, message: OutboundEmail) -> DeliveryReceipt:
        email = _build_message(self.config, message)
        connection: _SmtpConnection | None = None
        try:
            context = self._ssl_context_factory()
            context.minimum_version = ssl.TLSVersion.TLSv1_2
            if self.config.security == "implicit_tls":
                connection = self._smtp_ssl_factory(
                    host=self.config.host,
                    port=self.config.port,
                    timeout=self.config.timeout_seconds,
                    context=context,
                )
            else:
                connection = self._smtp_factory(
                    host=self.config.host,
                    port=self.config.port,
                    timeout=self.config.timeout_seconds,
                )
                connection.ehlo()
                connection.starttls(context=context)
                connection.ehlo()

            if self.config.username is not None:
                connection.login(self.config.username, self.config.password or "")
            refused = connection.send_message(
                email,
                from_addr=self.config.from_address,
                to_addrs=[message.recipient],
            )
            if refused:
                raise EmailDeliveryError(
                    "smtp_recipient_rejected",
                    retryable=False,
                )
            return DeliveryReceipt()
        except EmailDeliveryError:
            raise
        except smtplib.SMTPAuthenticationError:
            raise EmailDeliveryError(
                "smtp_authentication_failed",
                retryable=False,
            ) from None
        except smtplib.SMTPRecipientsRefused:
            raise EmailDeliveryError(
                "smtp_recipient_rejected",
                retryable=False,
            ) from None
        except smtplib.SMTPNotSupportedError:
            raise EmailDeliveryError(
                "smtp_tls_required",
                retryable=False,
            ) from None
        except smtplib.SMTPResponseException as error:
            temporary = 400 <= error.smtp_code < 500
            raise EmailDeliveryError(
                "smtp_temporary_failure" if temporary else "smtp_rejected",
                retryable=temporary,
            ) from None
        except (OSError, TimeoutError, smtplib.SMTPException):
            raise EmailDeliveryError(
                "smtp_unavailable",
                retryable=True,
            ) from None
        finally:
            if connection is not None:
                try:
                    connection.quit()
                except (OSError, smtplib.SMTPException):
                    try:
                        connection.close()
                    except (OSError, smtplib.SMTPException):
                        pass
                    # Shutdown failure must not replace an already determined
                    # send result or turn accepted DATA into a duplicate retry.


def build_email_sender(config: EmailDeliveryConfig) -> EmailSender | None:
    """Build the configured adapter without coupling auth to SMTP details."""

    if config.transport == "disabled":
        return None
    return SmtpEmailSender(config)


def _build_message(
    config: EmailDeliveryConfig,
    message: OutboundEmail,
) -> EmailMessage:
    recipient = _mailbox(message.recipient, "recipient")
    if _MESSAGE_ID.fullmatch(message.message_id) is None:
        raise ValueError("message id is invalid")
    if (
        not isinstance(message.subject, str)
        or not message.subject
        or len(message.subject) > _MAX_SUBJECT_CHARACTERS
        or "\r" in message.subject
        or "\n" in message.subject
    ):
        raise ValueError("email subject is invalid")
    if not isinstance(message.text_body, str) or not message.text_body:
        raise ValueError("email text body is required")
    if message.html_body is not None and not isinstance(message.html_body, str):
        raise ValueError("email HTML body must be text")
    size = len(message.text_body.encode("utf-8"))
    if message.html_body is not None:
        size += len(message.html_body.encode("utf-8"))
    if size > _MAX_BODY_BYTES:
        raise ValueError("email body is too large")

    value = EmailMessage(policy=SMTP)
    value["From"] = Address(
        display_name=config.from_name,
        addr_spec=config.from_address,
    )
    value["To"] = recipient
    value["Subject"] = message.subject
    value["Message-ID"] = message.message_id
    value.set_content(message.text_body)
    if message.html_body is not None:
        value.add_alternative(message.html_body, subtype="html")
    return value


def _mailbox(value: str, label: str) -> str:
    if (
        not isinstance(value, str)
        or not value
        or len(value.encode("utf-8")) > 254
        or value.count("@") != 1
        or not all(value.split("@", 1))
        or any(
            character.isspace() or ord(character) < 32 or ord(character) == 127
            for character in value
        )
    ):
        raise ValueError(f"email {label} is invalid")
    return value
