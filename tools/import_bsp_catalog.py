#!/usr/bin/env python3
"""Build a small app catalog and an optional local cover cache from BSP lists.

The generated JSON is suitable for bundling with the Flutter application. Cover
images are deliberately written to .catalog_cache/, which is gitignored and is
not bundled into the APK.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path


BASE_URL = "https://skab612.com/"
DEFAULT_EDITIONS = ("DDLU", "DSLU", "DMLU")
EDITION_METADATA = {
    "DDLU": {
        "series": "Dylan Dog",
        "edition": "Regularna (L)",
        "publisher": "Ludens",
    },
    "DSLU": {
        "series": "Dylan Dog",
        "edition": "Specijal (L)",
        "publisher": "Ludens",
    },
    "DMLU": {
        "series": "Dylan Dog",
        "edition": "Maxi (L)",
        "publisher": "Ludens",
    },
}
ROW_RE = re.compile(r"<tr\b[^>]*>(.*?)</tr>", re.IGNORECASE | re.DOTALL)
CELL_RE = re.compile(r"<td\b[^>]*>(.*?)</td>", re.IGNORECASE | re.DOTALL)
TAG_RE = re.compile(r"<[^>]+>")
ISSUE_RE = re.compile(
    r"site=bsp_info(?:&amp;|&)oznaka=([A-Z0-9]+)(?:&amp;|&)broj=(\d+)[^>]*>\s*(\d+)\.",
    re.IGNORECASE,
)
COVER_RE = re.compile(
    r"href=[\"']?(naslovnice_bsp/max_bsp/[a-z0-9_-]+\.jpe?g)",
    re.IGNORECASE,
)
PAGE_RE = re.compile(r"(?:&amp;|&)stranica=(\d+)", re.IGNORECASE)
CATALOG_METADATA_FIELDS = (
    "id",
    "sourceEdition",
    "series",
    "edition",
    "number",
    "title",
    "publisher",
    "year",
)


def clean_text(value: str) -> str:
    value = TAG_RE.sub("", value)
    return " ".join(html.unescape(value).split())


def catalog_metadata_signature(payload: object) -> str | None:
    """Return the versioned catalog metadata independently of cover assets."""
    if not isinstance(payload, dict):
        return None
    raw_issues = payload.get("issues")
    raw_editions = payload.get("editions")
    if not isinstance(raw_issues, list) or not isinstance(raw_editions, list):
        return None
    issues: list[dict[str, object]] = []
    for raw_issue in raw_issues:
        if not isinstance(raw_issue, dict):
            return None
        issues.append(
            {field: raw_issue.get(field) for field in CATALOG_METADATA_FIELDS}
        )
    issues.sort(key=lambda issue: str(issue["id"]))
    comparable = {
        "editions": sorted(str(edition) for edition in raw_editions),
        "issues": issues,
    }
    return json.dumps(comparable, ensure_ascii=False, sort_keys=True)


def fetch(
    url: str,
    destination: Path | None = None,
    *,
    use_cache: bool = False,
) -> bytes:
    if use_cache and destination is not None and destination.exists():
        return destination.read_bytes()
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "Comicollect catalog test importer/1.0"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        data = response.read()
    if destination is not None:
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    return data


def parse_issues(page_html: str, edition_code: str) -> list[dict[str, object]]:
    metadata = EDITION_METADATA.get(
        edition_code,
        {"series": edition_code, "edition": edition_code, "publisher": ""},
    )
    issues: list[dict[str, object]] = []
    for row in ROW_RE.findall(page_html):
        issue_match = ISSUE_RE.search(row)
        cells = CELL_RE.findall(row)
        if issue_match is None or len(cells) < 3:
            continue
        matched_code, source_number, display_number = issue_match.groups()
        if matched_code.upper() != edition_code:
            continue
        cover_match = COVER_RE.search(row)
        date = clean_text(cells[7]) if len(cells) > 7 else ""
        year_match = re.search(r"\b(19|20)\d{2}\b", date)
        number = int(display_number)
        cover_path = cover_match.group(1) if cover_match else ""
        issues.append(
            {
                "id": f"catalog-{edition_code}-{number}",
                "source": "BSP / Asteroid B612",
                "sourceEdition": edition_code,
                "sourceNumber": int(source_number),
                "series": metadata["series"],
                "edition": metadata["edition"],
                "number": number,
                "title": clean_text(cells[2]),
                "publisher": metadata["publisher"],
                "year": int(year_match.group(0)) if year_match else None,
                "published": date,
                "coverUrl": urllib.parse.urljoin(BASE_URL, cover_path)
                if cover_path
                else None,
            }
        )
    return issues


def import_edition(
    code: str,
    html_cache: Path,
    *,
    refresh: bool,
) -> list[dict[str, object]]:
    first_url = urllib.parse.urljoin(
        BASE_URL,
        f"index.php?site=bsp_popisi&oznaka={code}&stranica=1",
    )
    first_file = html_cache / f"{code.lower()}_1.html"
    first_html = fetch(
        first_url,
        first_file,
        use_cache=not refresh,
    ).decode("utf-8", errors="replace")
    pages = max((int(value) for value in PAGE_RE.findall(first_html)), default=1)
    issues = parse_issues(first_html, code)
    for page in range(2, pages + 1):
        time.sleep(0.15)
        url = urllib.parse.urljoin(
            BASE_URL,
            f"index.php?site=bsp_popisi&oznaka={code}&stranica={page}",
        )
        page_file = html_cache / f"{code.lower()}_{page}.html"
        page_html = fetch(
            url,
            page_file,
            use_cache=not refresh,
        ).decode("utf-8", errors="replace")
        issues.extend(parse_issues(page_html, code))
    unique = {str(issue["id"]): issue for issue in issues}
    return sorted(unique.values(), key=lambda issue: int(issue["number"]))


def download_covers(issues: list[dict[str, object]], cover_cache: Path) -> None:
    total = len(issues)
    for index, issue in enumerate(issues, start=1):
        cover_url = issue.get("coverUrl")
        if not cover_url:
            continue
        edition = str(issue["sourceEdition"]).lower()
        suffix = Path(urllib.parse.urlparse(str(cover_url)).path).suffix or ".jpg"
        destination = cover_cache / edition / f"{int(issue['number']):04d}{suffix}"
        if destination.exists():
            continue
        print(f"[{index}/{total}] {issue['id']}")
        fetch(str(cover_url), destination)
        time.sleep(0.1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--editions", nargs="+", default=DEFAULT_EDITIONS)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("app/assets/catalog/bsp_catalog.json"),
    )
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=Path(".catalog_cache/bsp"),
    )
    parser.add_argument("--download-covers", action="store_true")
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="Ponovno preuzmi HTML popise umjesto korištenja lokalnog cachea.",
    )
    parser.add_argument(
        "--catalog-version",
        type=int,
        help=(
            "Verzija kataloga ugrađena u aplikaciju. Ako nije zadana, zadržava "
            "se verzija iz postojeće izlazne datoteke ili se koristi 1."
        ),
    )
    args = parser.parse_args()

    existing_payload: object | None = None
    existing_version: int | None = None
    if args.output.exists():
        try:
            existing_payload = json.loads(args.output.read_text(encoding="utf-8"))
            parsed_version = (
                existing_payload.get("catalogVersion")
                if isinstance(existing_payload, dict)
                else None
            )
            if isinstance(parsed_version, int) and not isinstance(
                parsed_version, bool
            ):
                existing_version = parsed_version
        except (OSError, json.JSONDecodeError, AttributeError):
            pass
    catalog_version = args.catalog_version
    if (
        catalog_version is not None
        and existing_version is not None
        and catalog_version <= existing_version
    ):
        parser.error(
            "--catalog-version mora biti veći od postojeće verzije "
            f"{existing_version}; za identičan rebuild izostavi argument"
        )
    if catalog_version is None:
        catalog_version = existing_version
    if catalog_version is None:
        catalog_version = 1
    if catalog_version < 1:
        parser.error("--catalog-version mora biti pozitivan cijeli broj")

    editions = [code.upper() for code in args.editions]
    issues: list[dict[str, object]] = []
    for edition in editions:
        print(f"Importing {edition}")
        issues.extend(
            import_edition(
                edition,
                args.cache_dir / "html",
                refresh=args.refresh,
            )
        )

    payload = {
        "schemaVersion": 1,
        "catalogVersion": catalog_version,
        "source": {
            "name": "BSP / Strip-knjižara Asteroid B612",
            "url": BASE_URL,
            "note": "Testni uvoz; provjeriti dopuštenje prije distribucije slika.",
        },
        "editions": editions,
        "issues": issues,
    }
    if (
        args.catalog_version is None
        and existing_version is not None
        and catalog_metadata_signature(existing_payload)
        != catalog_metadata_signature(payload)
    ):
        parser.error(
            "sadržaj kataloga se promijenio; ponovi uvoz s "
            f"--catalog-version {existing_version + 1} ili većom"
        )

    if args.download_covers:
        download_covers(issues, args.cache_dir / "covers")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {len(issues)} issues to {args.output}")


if __name__ == "__main__":
    main()
