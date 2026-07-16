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
        self.pepper.write_bytes(b"short")
        with self.assertRaisesRegex(ValueError, "at least 32"):
            load_config(self.environment())

        self.pepper.write_bytes(b"p" * 32)
        with self.assertRaisesRegex(ValueError, "production minimum"):
            load_config(
                self.environment(
                    COMICOLLECT_SCRYPT_N="16",
                    COMICOLLECT_SCRYPT_R="1",
                    COMICOLLECT_SCRYPT_P="1",
                )
            )

    def test_pepper_file_must_not_be_group_or_world_writable(self) -> None:
        self.pepper.chmod(0o666)

        with self.assertRaisesRegex(ValueError, "must not be group/world writable"):
            load_config(self.environment())

    def test_storage_limits_must_be_positive_and_bounded(self) -> None:
        for key, value in (
            ("COMICOLLECT_TENANT_STORAGE_LIMIT_BYTES", "0"),
            ("COMICOLLECT_DISK_RESERVE_BYTES", str(101 * 1024**3)),
        ):
            with self.subTest(key=key):
                with self.assertRaisesRegex(ValueError, "bytes"):
                    load_config(self.environment(**{key: value}))

    def test_binary_pepper_bytes_are_not_trimmed(self) -> None:
        pepper = b"\n" + (b"p" * 32) + b"\t"
        self.pepper.write_bytes(pepper)

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
