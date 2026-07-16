from __future__ import annotations

import unittest

from comicollect_backend.auth_models import AuthError
from comicollect_backend.rate_limit import RateLimiter, RatePolicy


class RateLimiterTest(unittest.TestCase):
    def test_bucket_policies_are_independent_and_reset_after_the_window(self) -> None:
        now = 1_000
        limiter = RateLimiter(
            clock=lambda: now,
            limit=9,
            window_ms=9_000,
            policies={"strict": RatePolicy(1, 1_000)},
        )

        limiter.consume("strict", "shared-ip")
        with self.assertRaises(AuthError) as captured:
            limiter.consume("strict", "shared-ip")
        self.assertEqual(captured.exception.code, "rate_limited")
        self.assertEqual(captured.exception.headers["Retry-After"], "1")

        limiter.consume("other", "shared-ip")
        now += 1_000
        limiter.consume("strict", "shared-ip")

    def test_invalid_policy_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "policy values"):
            RateLimiter(
                clock=lambda: 0,
                policies={"broken": RatePolicy(0, 1_000)},
            )


if __name__ == "__main__":
    unittest.main()
