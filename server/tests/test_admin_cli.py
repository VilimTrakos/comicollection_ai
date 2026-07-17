from __future__ import annotations

import tempfile
import unittest
from io import StringIO
from pathlib import Path
from unittest.mock import patch

from comicollect_backend.admin_cli import _parser, create_account, main

from tests.support import PASSWORD, make_auth_service, token_from


class AdminCliTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.service = make_auth_service(
            Path(self.temporary.name) / "accounts.sqlite3",
            registration_enabled=False,
        )

    def test_operator_can_create_first_account_while_registration_is_closed(
        self,
    ) -> None:
        prompts: list[str] = []
        passwords = iter((PASSWORD, PASSWORD))
        output = StringIO()
        errors = StringIO()

        result = create_account(
            self.service,
            email="  FIRST@Example.com ",
            display_name="First Collector",
            password_reader=lambda prompt: (
                prompts.append(prompt),
                next(passwords),
            )[1],
            stdout=output,
            stderr=errors,
        )

        self.assertEqual(result, 0)
        self.assertEqual(errors.getvalue(), "")
        self.assertEqual(len(prompts), 2)
        self.assertNotIn(PASSWORD, output.getvalue())
        self.assertNotIn(PASSWORD, errors.getvalue())
        self.assertNotIn("first@example.com", output.getvalue())
        self.assertNotIn(
            PASSWORD.encode(),
            self.service.repository.path.read_bytes(),
        )
        logged_in = self.service.login(
            email="first@example.com",
            password=PASSWORD,
            installation_id="operator-created-login",
        )
        self.assertTrue(token_from(logged_in, "access_token"))

    def test_password_mismatch_never_creates_or_discloses_an_account(self) -> None:
        passwords = iter((PASSWORD, PASSWORD + "different"))
        output = StringIO()
        errors = StringIO()

        result = create_account(
            self.service,
            email="missing@example.com",
            display_name="Missing",
            password_reader=lambda _: next(passwords),
            stdout=output,
            stderr=errors,
        )

        self.assertEqual(result, 2)
        self.assertEqual(output.getvalue(), "")
        self.assertNotIn(PASSWORD, errors.getvalue())
        self.assertIsNone(
            self.service.repository.account_with_password("missing@example.com")
        )

    def test_operator_account_uses_the_same_password_policy(self) -> None:
        output = StringIO()
        errors = StringIO()
        passwords = iter(("too-short", "too-short"))

        result = create_account(
            self.service,
            email="policy@example.com",
            display_name="Policy",
            password_reader=lambda _: next(passwords),
            stdout=output,
            stderr=errors,
        )

        self.assertEqual(result, 1)
        self.assertIn("password_policy_failed", errors.getvalue())
        self.assertNotIn("too-short", errors.getvalue())
        self.assertIsNone(
            self.service.repository.account_with_password("policy@example.com")
        )

    def test_cli_accepts_no_password_argument_and_delegates_to_secure_prompt(self) -> None:
        help_text = _parser().format_help()
        self.assertNotIn("--password", help_text)
        output = StringIO()
        errors = StringIO()
        passwords = iter((PASSWORD, PASSWORD))

        with patch(
            "comicollect_backend.admin_cli._service_from_environment",
            return_value=self.service,
        ):
            result = main(
                (
                    "create-account",
                    "--email",
                    "cli@example.com",
                    "--display-name",
                    "CLI Collector",
                ),
                environ={},
                password_reader=lambda _: next(passwords),
                stdout=output,
                stderr=errors,
            )

        self.assertEqual(result, 0)
        self.assertNotIn(PASSWORD, output.getvalue() + errors.getvalue())


if __name__ == "__main__":
    unittest.main()
