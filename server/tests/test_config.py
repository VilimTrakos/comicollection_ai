from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from comicollect_backend.config import (
    MAX_ACCESS_TTL_SECONDS,
    MAX_REFRESH_TTL_SECONDS,
    MAX_SESSION_TTL_SECONDS,
    load_config,
)
from comicollect_backend.passwords import (
    MAX_SCRYPT_DKLEN,
    MAX_SCRYPT_MAXMEM,
    MAX_SCRYPT_N,
    MAX_SCRYPT_P,
    MAX_SCRYPT_R,
)


class ProductionConfigTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.pepper = self.root / "password-pepper"
        self.pepper.write_bytes(b"p" * 32)
        self.pepper.chmod(0o440)

    def environment(self, **overrides: str) -> dict[str, str]:
        values = {
            "COMICOLLECT_DATA_ROOT": str(self.root),
            "COMICOLLECT_PASSWORD_PEPPER_FILE": str(self.pepper),
            "COMICOLLECT_HOST": "127.0.0.1",
            "COMICOLLECT_PORT": "9876",
            "COMICOLLECT_PUBLIC_REGISTRATION": "false",
        }
        values.update(overrides)
        return values

    def write_pepper(self, value: bytes) -> None:
        self.pepper.chmod(0o640)
        self.pepper.write_bytes(value)
        self.pepper.chmod(0o440)

    def smtp_environment(self, **overrides: str) -> dict[str, str]:
        password = self.root / "smtp-password"
        if password.exists():
            password.chmod(0o640)
        password.write_text("smtp-secret\n", encoding="utf-8")
        password.chmod(0o440)
        values = self.environment(
            COMICOLLECT_EMAIL_TRANSPORT="smtp",
            COMICOLLECT_SMTP_HOST="smtp.example.test",
            COMICOLLECT_SMTP_SECURITY="starttls",
            COMICOLLECT_SMTP_USERNAME="mailer-user",
            COMICOLLECT_SMTP_PASSWORD_FILE=str(password),
            COMICOLLECT_SMTP_TIMEOUT_SECONDS="8",
            COMICOLLECT_EMAIL_FROM_ADDRESS="noreply@example.test",
            COMICOLLECT_EMAIL_FROM_NAME="Comicollect Accounts",
        )
        values.update(overrides)
        return values

    def test_loads_typed_production_configuration(self) -> None:
        config = load_config(self.environment())

        self.assertEqual(config.auth_database, self.root / "accounts.sqlite3")
        self.assertEqual(config.tenant_root, self.root / "accounts")
        self.assertEqual(config.password_pepper, b"p" * 32)
        self.assertEqual(config.host, "127.0.0.1")
        self.assertEqual(config.port, 9876)
        self.assertFalse(config.registration_enabled)
        self.assertEqual(config.tenant_storage_limit_bytes, 512 * 1024 * 1024)
        self.assertEqual(config.disk_reserve_bytes, 1024 * 1024 * 1024)
        self.assertEqual(config.backup_reserve_bytes, 1024 * 1024 * 1024)
        self.assertEqual(config.email_delivery.transport, "disabled")

    def test_loads_tls_only_smtp_configuration_and_protected_secret(self) -> None:
        config = load_config(
            self.smtp_environment(COMICOLLECT_PUBLIC_REGISTRATION="true")
        )

        email = config.email_delivery
        self.assertTrue(config.registration_enabled)
        self.assertEqual(email.transport, "smtp")
        self.assertEqual(email.host, "smtp.example.test")
        self.assertEqual(email.port, 587)
        self.assertEqual(email.security, "starttls")
        self.assertEqual(email.username, "mailer-user")
        self.assertEqual(email.password, "smtp-secret\n")
        self.assertEqual(email.timeout_seconds, 8)
        self.assertEqual(email.from_address, "noreply@example.test")
        self.assertEqual(email.from_name, "Comicollect Accounts")
        self.assertNotIn("smtp-secret", repr(email))

    def test_implicit_tls_uses_its_standard_port_by_default(self) -> None:
        config = load_config(
            self.smtp_environment(COMICOLLECT_SMTP_SECURITY="implicit_tls")
        )

        self.assertEqual(config.email_delivery.security, "implicit_tls")
        self.assertEqual(config.email_delivery.port, 465)

    def test_public_registration_fails_closed_without_email_delivery(self) -> None:
        with self.assertRaisesRegex(ValueError, "registration requires"):
            load_config(
                self.environment(COMICOLLECT_PUBLIC_REGISTRATION="true")
            )

    def test_smtp_rejects_plaintext_unknown_or_unbounded_configuration(self) -> None:
        cases = (
            ({"COMICOLLECT_EMAIL_TRANSPORT": "sendmail"}, "TRANSPORT"),
            ({"COMICOLLECT_SMTP_SECURITY": "plaintext"}, "SECURITY"),
            ({"COMICOLLECT_SMTP_PORT": "0"}, "PORT"),
            ({"COMICOLLECT_SMTP_TIMEOUT_SECONDS": "31"}, "TIMEOUT"),
            ({"COMICOLLECT_EMAIL_FROM_ADDRESS": "bad address"}, "FROM_ADDRESS"),
        )
        for overrides, expected in cases:
            with self.subTest(overrides=overrides), self.assertRaisesRegex(
                ValueError,
                expected,
            ):
                environment = (
                    self.environment(**overrides)
                    if "COMICOLLECT_EMAIL_TRANSPORT" in overrides
                    else self.smtp_environment(**overrides)
                )
                load_config(environment)

    def test_smtp_credentials_must_be_paired_and_unambiguous(self) -> None:
        password_file = str(self.root / "smtp-password")
        cases = (
            {"COMICOLLECT_SMTP_USERNAME": ""},
            {"COMICOLLECT_SMTP_PASSWORD_FILE": ""},
            {
                "COMICOLLECT_SMTP_PASSWORD": "inline-secret",
                "COMICOLLECT_SMTP_PASSWORD_FILE": password_file,
            },
        )
        for overrides in cases:
            with self.subTest(overrides=overrides), self.assertRaises(ValueError):
                load_config(self.smtp_environment(**overrides))

    def test_smtp_password_file_must_be_absolute_regular_and_read_only(self) -> None:
        password = self.root / "smtp-password"
        environment = self.smtp_environment()
        password.chmod(0o640)
        with self.assertRaisesRegex(ValueError, "read-only"):
            load_config(environment)

        password.chmod(0o440)
        environment["COMICOLLECT_SMTP_PASSWORD_FILE"] = "relative-secret"
        with self.assertRaisesRegex(ValueError, "absolute"):
            load_config(environment)

        target = self.root / "smtp-password-target"
        target.write_text("secret", encoding="utf-8")
        target.chmod(0o440)
        link = self.root / "smtp-password-link"
        link.symlink_to(target)
        environment["COMICOLLECT_SMTP_PASSWORD_FILE"] = str(link)
        with self.assertRaisesRegex(ValueError, "regular file"):
            load_config(environment)

    def test_disabled_email_transport_rejects_stray_smtp_settings(self) -> None:
        with self.assertRaisesRegex(ValueError, "require.*smtp"):
            load_config(
                self.environment(COMICOLLECT_SMTP_HOST="smtp.example.test")
            )

    def test_production_fails_closed_without_exactly_one_password_pepper(self) -> None:
        environment = self.environment()
        del environment["COMICOLLECT_PASSWORD_PEPPER_FILE"]
        with self.assertRaisesRegex(ValueError, "exactly one"):
            load_config(environment)

        with self.assertRaisesRegex(ValueError, "exactly one"):
            load_config(
                self.environment(COMICOLLECT_PASSWORD_PEPPER="x" * 32)
            )

    def test_rejects_unknown_boolean_and_invalid_token_lifetimes(self) -> None:
        with self.assertRaisesRegex(ValueError, "boolean"):
            load_config(
                self.environment(COMICOLLECT_PUBLIC_REGISTRATION="sometimes")
            )
        with self.assertRaisesRegex(ValueError, "access < refresh"):
            load_config(
                self.environment(
                    COMICOLLECT_ACCESS_TTL_SECONDS="100",
                    COMICOLLECT_REFRESH_TTL_SECONDS="100",
                )
            )

    def test_storage_and_secret_file_paths_must_be_absolute(self) -> None:
        with self.assertRaisesRegex(ValueError, "DATA_ROOT must be an absolute"):
            load_config(
                self.environment(COMICOLLECT_DATA_ROOT="relative-data")
            )
        with self.assertRaisesRegex(
            ValueError,
            "PASSWORD_PEPPER_FILE must be an absolute",
        ):
            load_config(
                self.environment(
                    COMICOLLECT_PASSWORD_PEPPER_FILE="relative-pepper"
                )
            )

    def test_secret_file_and_scrypt_cost_must_meet_production_minimum(self) -> None:
        self.write_pepper(b"short")
        with self.assertRaisesRegex(ValueError, "at least 32"):
            load_config(self.environment())

        self.write_pepper(b"p" * 32)
        with self.assertRaisesRegex(ValueError, "production minimum"):
            load_config(
                self.environment(
                    COMICOLLECT_SCRYPT_N="16",
                    COMICOLLECT_SCRYPT_R="1",
                    COMICOLLECT_SCRYPT_P="1",
                )
            )

    def test_pepper_permissions_allow_reads_but_reject_unsafe_access(self) -> None:
        for mode in (0o400, 0o440):
            with self.subTest(allowed=oct(mode)):
                self.pepper.chmod(mode)
                self.assertEqual(load_config(self.environment()).password_pepper, b"p" * 32)

        for mode in (0o600, 0o640, 0o644, 0o660, 0o740, 0o650):
            with self.subTest(rejected=oct(mode)):
                self.pepper.chmod(mode)
                with self.assertRaisesRegex(ValueError, "read-only"):
                    load_config(self.environment())

    def test_pepper_path_must_not_be_a_symbolic_link(self) -> None:
        target = self.root / "pepper-target"
        target.write_bytes(b"p" * 32)
        target.chmod(0o440)
        link = self.root / "pepper-link"
        link.symlink_to(target)

        with self.assertRaisesRegex(ValueError, "regular file"):
            load_config(
                self.environment(COMICOLLECT_PASSWORD_PEPPER_FILE=str(link))
            )

    def test_storage_limits_must_be_positive_and_bounded(self) -> None:
        for key, value in (
            ("COMICOLLECT_TENANT_STORAGE_LIMIT_BYTES", "0"),
            ("COMICOLLECT_DISK_RESERVE_BYTES", str(101 * 1024**3)),
            ("COMICOLLECT_BACKUP_RESERVE_BYTES", str(101 * 1024**3)),
        ):
            with self.subTest(key=key):
                with self.assertRaisesRegex(ValueError, "bytes"):
                    load_config(self.environment(**{key: value}))

    def test_binary_pepper_bytes_are_not_trimmed(self) -> None:
        pepper = b"\n" + (b"p" * 32) + b"\t"
        self.write_pepper(pepper)

        self.assertEqual(load_config(self.environment()).password_pepper, pepper)

    def test_token_lifetimes_have_safe_production_maximums(self) -> None:
        cases = (
            ("COMICOLLECT_ACCESS_TTL_SECONDS", MAX_ACCESS_TTL_SECONDS + 1),
            ("COMICOLLECT_REFRESH_TTL_SECONDS", MAX_REFRESH_TTL_SECONDS + 1),
            ("COMICOLLECT_SESSION_TTL_SECONDS", MAX_SESSION_TTL_SECONDS + 1),
        )
        for key, value in cases:
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "maximum"):
                load_config(self.environment(**{key: str(value)}))

    def test_scrypt_parameters_have_safe_production_maximums(self) -> None:
        cases = (
            ("COMICOLLECT_SCRYPT_N", MAX_SCRYPT_N * 2),
            ("COMICOLLECT_SCRYPT_R", MAX_SCRYPT_R + 1),
            ("COMICOLLECT_SCRYPT_P", MAX_SCRYPT_P + 1),
            ("COMICOLLECT_SCRYPT_DKLEN", MAX_SCRYPT_DKLEN + 1),
            ("COMICOLLECT_SCRYPT_MAXMEM", MAX_SCRYPT_MAXMEM + 1),
        )
        for key, value in cases:
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "maximum"):
                load_config(self.environment(**{key: str(value)}))


if __name__ == "__main__":
    unittest.main()
