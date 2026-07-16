from __future__ import annotations

import unittest

from comicollect_backend.passwords import PasswordHasher, ScryptParams

from tests.support import PASSWORD, PEPPER, make_hasher


class PasswordHasherTest(unittest.TestCase):
    def test_hashes_are_salted_and_verify_without_containing_password(self) -> None:
        hasher = make_hasher()
        first = hasher.hash(PASSWORD)
        second = hasher.hash(PASSWORD)

        self.assertNotEqual(first, second)
        self.assertNotIn(PASSWORD, first)
        self.assertTrue(hasher.verify(PASSWORD, first))
        self.assertFalse(hasher.needs_rehash(first))
        self.assertFalse(hasher.verify("definitely wrong", first))

    def test_malformed_hash_is_an_invalid_credential_not_a_server_error(self) -> None:
        hasher = make_hasher()
        self.assertFalse(hasher.verify(PASSWORD, "not-a-password-hash"))
        self.assertTrue(hasher.needs_rehash("not-a-password-hash"))

    def test_old_cost_is_marked_for_rehash(self) -> None:
        old = make_hasher(pepper=PEPPER, n=16)
        encoded = old.hash(PASSWORD)
        current = make_hasher(pepper=PEPPER, n=32)

        self.assertTrue(current.verify(PASSWORD, encoded))
        self.assertTrue(current.needs_rehash(encoded))

    def test_operational_maxmem_change_does_not_require_rehash(self) -> None:
        encoded = make_hasher(pepper=PEPPER, n=32).hash(PASSWORD)
        current = PasswordHasher(
            PEPPER,
            ScryptParams(
                n=32,
                r=1,
                p=1,
                dklen=32,
                maxmem=256 * 1024 * 1024,
            ),
        )

        self.assertTrue(current.verify(PASSWORD, encoded))
        self.assertFalse(current.needs_rehash(encoded))

    def test_password_input_bounds_are_enforced_before_expensive_hashing(self) -> None:
        hasher = make_hasher()
        for invalid in ("short", "x" * 129, "ž" * 600):
            with self.subTest(length=len(invalid)):
                with self.assertRaises(ValueError):
                    hasher.hash(invalid)


if __name__ == "__main__":
    unittest.main()
