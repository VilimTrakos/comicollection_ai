"""Bounded in-process auth throttling; the edge proxy remains the first tier."""

from __future__ import annotations

import hashlib
import math
from collections import OrderedDict
from dataclasses import dataclass
from threading import Lock
from typing import Callable, Mapping

from .auth_models import AuthError


@dataclass(frozen=True)
class RatePolicy:
    limit: int
    window_ms: int

    def validate(self) -> None:
        if min(self.limit, self.window_ms) <= 0:
            raise ValueError("rate limit policy values must be positive")


class RateLimiter:
    def __init__(
        self,
        *,
        clock: Callable[[], int],
        limit: int = 10,
        window_ms: int = 60_000,
        maximum_keys: int = 10_000,
        policies: Mapping[str, RatePolicy] | None = None,
    ):
        if min(limit, window_ms, maximum_keys) <= 0:
            raise ValueError("rate limit values must be positive")
        self.clock = clock
        self.limit = limit
        self.window_ms = window_ms
        self.maximum_keys = maximum_keys
        self.policies = dict(policies or {})
        for policy in self.policies.values():
            policy.validate()
        self._entries: OrderedDict[bytes, tuple[int, int]] = OrderedDict()
        self._lock = Lock()

    def consume(self, bucket: str, identity: str) -> None:
        policy = self.policies.get(
            bucket,
            RatePolicy(self.limit, self.window_ms),
        )
        key = hashlib.sha256(f"{bucket}\0{identity}".encode()).digest()
        now = self.clock()
        with self._lock:
            start, count = self._entries.pop(key, (now, 0))
            if now - start >= policy.window_ms:
                start, count = now, 0
            if count >= policy.limit:
                self._entries[key] = (start, count)
                remaining_ms = max(1, policy.window_ms - (now - start))
                raise AuthError(
                    429,
                    "rate_limited",
                    "Too many attempts",
                    headers={"Retry-After": str(math.ceil(remaining_ms / 1000))},
                )
            self._entries[key] = (start, count + 1)
            while len(self._entries) > self.maximum_keys:
                self._entries.popitem(last=False)
