#!/usr/bin/env python3
"""Bounded loopback startup probe used by the production systemd unit."""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request


def main() -> int:
    port = int(os.getenv("COMICOLLECT_PORT", "8787"))
    if not 1 <= port <= 65535:
        raise SystemExit("COMICOLLECT_PORT is invalid")
    base = f"http://127.0.0.1:{port}"
    for attempt in range(20):
        try:
            if all(_healthy(base + path) for path in ("/health/live", "/health/ready")):
                return 0
        except (OSError, ValueError, urllib.error.URLError):
            pass
        if attempt < 19:
            time.sleep(0.5)
    raise SystemExit("production API did not become ready on loopback")


def _healthy(url: str) -> bool:
    request = urllib.request.Request(url, headers={"Connection": "close"})
    with urllib.request.urlopen(request, timeout=1.5) as response:
        if response.status != 200 or response.headers.get_content_type() != "application/json":
            return False
        payload = response.read(1024)
        return json.loads(payload) == {"ok": True}


if __name__ == "__main__":
    raise SystemExit(main())
