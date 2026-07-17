from __future__ import annotations

import smtplib
import ssl
import unittest

from comicollect_backend.config import EmailDeliveryConfig
from comicollect_backend.email_delivery import (
    EmailDeliveryError,
    OutboundEmail,
    SmtpEmailSender,
    build_email_sender,
)


class SmtpEmailSenderTest(unittest.TestCase):
    def test_starttls_delivery_upgrades_before_authentication_and_send(self) -> None:
        connection = _FakeSmtpConnection()
        calls: list[dict] = []
        config = _config(security="starttls")
        sender = SmtpEmailSender(
            config,
            smtp_factory=lambda **kwargs: calls.append(kwargs) or connection,
            smtp_ssl_factory=_unexpected_factory,
        )

        receipt = sender.send(_message())

        self.assertIsNone(receipt.provider_message_id)
        self.assertEqual(
            connection.events,
            ["ehlo", "starttls", "ehlo", "login", "send", "quit"],
        )
        self.assertEqual(
            calls,
            [{"host": "smtp.example.test", "port": 587, "timeout": 7}],
        )
        self.assertEqual(connection.login_value, ("smtp-user", "smtp-secret"))
        self.assertEqual(connection.from_addr, "noreply@example.test")
        self.assertEqual(connection.to_addrs, ["reader@example.test"])
        self.assertEqual(
            str(connection.message["From"]),
            "Comicollect <noreply@example.test>",
        )
        self.assertEqual(str(connection.message["To"]), "reader@example.test")
        self.assertEqual(str(connection.message["Subject"]), "Confirm your account")
        self.assertEqual(
            str(connection.message["Message-ID"]),
            "<outbox-1@mail.comicollect.example>",
        )
        self.assertEqual(
            connection.message.get_body(preferencelist=("plain",)).get_content(),
            "Open the secure link.\n",
        )
        self.assertEqual(
            connection.message.get_body(preferencelist=("html",)).get_content(),
            "<p>Open the secure link.</p>\n",
        )

    def test_implicit_tls_uses_ssl_factory_without_starttls(self) -> None:
        connection = _FakeSmtpConnection()
        calls: list[dict] = []
        config = _config(
            security="implicit_tls",
            port=465,
            username=None,
            password=None,
        )
        sender = SmtpEmailSender(
            config,
            smtp_factory=_unexpected_factory,
            smtp_ssl_factory=lambda **kwargs: calls.append(kwargs) or connection,
        )

        sender.send(_message())

        self.assertEqual(connection.events, ["send", "quit"])
        self.assertEqual(calls[0]["host"], "smtp.example.test")
        self.assertEqual(calls[0]["port"], 465)
        self.assertEqual(calls[0]["timeout"], 7)
        self.assertEqual(
            calls[0]["context"].minimum_version,
            ssl.TLSVersion.TLSv1_2,
        )

    def test_delivery_errors_are_classified_without_provider_details(self) -> None:
        cases = (
            (
                smtplib.SMTPAuthenticationError(535, b"secret provider detail"),
                "smtp_authentication_failed",
                False,
            ),
            (
                smtplib.SMTPDataError(451, b"temporary recipient detail"),
                "smtp_temporary_failure",
                True,
            ),
            (
                smtplib.SMTPDataError(554, b"permanent recipient detail"),
                "smtp_rejected",
                False,
            ),
            (
                smtplib.SMTPNotSupportedError("STARTTLS unavailable"),
                "smtp_tls_required",
                False,
            ),
            (OSError("private network detail"), "smtp_unavailable", True),
        )
        for failure, code, retryable in cases:
            with self.subTest(code=code):
                connection = _FakeSmtpConnection(send_error=failure)
                sender = SmtpEmailSender(
                    _config(),
                    smtp_factory=lambda **_: connection,
                )

                with self.assertRaises(EmailDeliveryError) as caught:
                    sender.send(_message())

                self.assertEqual(str(caught.exception), "Email delivery failed")
                self.assertEqual(caught.exception.code, code)
                self.assertEqual(caught.exception.retryable, retryable)
                self.assertIsNone(caught.exception.__cause__)
                self.assertNotIn("detail", repr(caught.exception))

    def test_refused_recipient_is_a_permanent_sanitized_failure(self) -> None:
        connection = _FakeSmtpConnection(
            refused={"reader@example.test": (550, b"private diagnostic")},
        )
        sender = SmtpEmailSender(
            _config(),
            smtp_factory=lambda **_: connection,
        )

        with self.assertRaises(EmailDeliveryError) as caught:
            sender.send(_message())

        self.assertEqual(caught.exception.code, "smtp_recipient_rejected")
        self.assertFalse(caught.exception.retryable)

    def test_shutdown_failure_after_accepted_data_does_not_trigger_retry(self) -> None:
        connection = _FakeSmtpConnection(
            quit_error=smtplib.SMTPServerDisconnected("private shutdown detail"),
        )
        sender = SmtpEmailSender(
            _config(),
            smtp_factory=lambda **_: connection,
        )

        sender.send(_message())

        self.assertEqual(connection.events[-2:], ["quit", "close"])

    def test_rejects_header_injection_before_opening_a_connection(self) -> None:
        opened = False

        def factory(**_):
            nonlocal opened
            opened = True
            return _FakeSmtpConnection()

        sender = SmtpEmailSender(_config(), smtp_factory=factory)

        with self.assertRaisesRegex(ValueError, "subject"):
            sender.send(
                OutboundEmail(
                    message_id="<outbox-1@mail.comicollect.example>",
                    recipient="reader@example.test",
                    subject="Safe\nBcc: victim@example.test",
                    text_body="Body",
                )
            )

        self.assertFalse(opened)

    def test_disabled_transport_builds_no_sender_and_safe_password_repr(self) -> None:
        disabled = EmailDeliveryConfig(
            transport="disabled",
            host="",
            port=0,
            security="",
            username=None,
            password=None,
            from_address="",
            from_name="",
            timeout_seconds=0,
        )

        self.assertIsNone(build_email_sender(disabled))
        self.assertIsInstance(build_email_sender(_config()), SmtpEmailSender)
        self.assertNotIn("smtp-secret", repr(_config()))


class _FakeSmtpConnection:
    def __init__(
        self,
        *,
        send_error: BaseException | None = None,
        refused: dict | None = None,
        quit_error: BaseException | None = None,
    ):
        self.send_error = send_error
        self.refused = refused or {}
        self.quit_error = quit_error
        self.events: list[str] = []
        self.login_value: tuple[str, str] | None = None
        self.message = None
        self.from_addr = None
        self.to_addrs = None

    def ehlo(self):
        self.events.append("ehlo")

    def starttls(self, *, context):
        self.events.append("starttls")
        self.tls_context = context

    def login(self, user: str, password: str):
        self.events.append("login")
        self.login_value = (user, password)

    def send_message(self, msg, from_addr: str, to_addrs: list[str]):
        self.events.append("send")
        if self.send_error is not None:
            raise self.send_error
        self.message = msg
        self.from_addr = from_addr
        self.to_addrs = to_addrs
        return self.refused

    def quit(self):
        self.events.append("quit")
        if self.quit_error is not None:
            raise self.quit_error

    def close(self):
        self.events.append("close")


def _config(
    *,
    security: str = "starttls",
    port: int = 587,
    username: str | None = "smtp-user",
    password: str | None = "smtp-secret",
) -> EmailDeliveryConfig:
    return EmailDeliveryConfig(
        transport="smtp",
        host="smtp.example.test",
        port=port,
        security=security,
        username=username,
        password=password,
        from_address="noreply@example.test",
        from_name="Comicollect",
        timeout_seconds=7,
    )


def _message() -> OutboundEmail:
    return OutboundEmail(
        message_id="<outbox-1@mail.comicollect.example>",
        recipient="reader@example.test",
        subject="Confirm your account",
        text_body="Open the secure link.",
        html_body="<p>Open the secure link.</p>",
    )


def _unexpected_factory(**_):
    raise AssertionError("unexpected SMTP factory")


if __name__ == "__main__":
    unittest.main()
