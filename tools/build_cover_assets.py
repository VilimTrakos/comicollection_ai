#!/usr/bin/env python3
"""Compress cached BSP covers into Flutter assets and add visual signatures."""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import tempfile
from pathlib import Path


def run(command: list[str], library_path: Path | None) -> None:
    environment = os.environ.copy()
    if library_path is not None:
        environment["LD_LIBRARY_PATH"] = str(library_path)
    subprocess.run(command, check=True, env=environment)


def read_ppm(path: Path) -> tuple[int, int, bytes]:
    data = path.read_bytes()
    if not data.startswith(b"P6"):
        raise ValueError(f"Unsupported PPM file: {path}")
    offset = 2
    tokens: list[bytes] = []
    while len(tokens) < 3:
        while offset < len(data) and data[offset] in b" \t\r\n":
            offset += 1
        if data[offset : offset + 1] == b"#":
            offset = data.index(b"\n", offset) + 1
            continue
        end = offset
        while end < len(data) and data[end] not in b" \t\r\n":
            end += 1
        tokens.append(data[offset:end])
        offset = end
    while offset < len(data) and data[offset] in b" \t\r\n":
        offset += 1
    width, height, maximum = (int(token) for token in tokens)
    if maximum != 255:
        raise ValueError(f"Unsupported PPM channel range: {maximum}")
    pixels = data[offset : offset + width * height * 3]
    if len(pixels) != width * height * 3:
        raise ValueError(f"Incomplete PPM pixel data: {path}")
    return width, height, pixels


def visual_signature(
    cover: Path,
    dwebp: Path,
    library_path: Path | None,
) -> tuple[str, str]:
    with tempfile.NamedTemporaryFile(suffix=".ppm") as temporary:
        run(
            [
                str(dwebp),
                str(cover),
                "-quiet",
                "-ppm",
                "-resize",
                "9",
                "8",
                "-o",
                temporary.name,
            ],
            library_path,
        )
        width, height, pixels = read_ppm(Path(temporary.name))

    def rgb(x: int, y: int) -> tuple[int, int, int]:
        index = (y * width + x) * 3
        return pixels[index], pixels[index + 1], pixels[index + 2]

    bits = 0
    bit_index = 0
    for y in range(height):
        for x in range(width - 1):
            left = rgb(x, y)
            right = rgb(x + 1, y)
            left_luma = 299 * left[0] + 587 * left[1] + 114 * left[2]
            right_luma = 299 * right[0] + 587 * right[1] + 114 * right[2]
            if left_luma > right_luma:
                bits |= 1 << bit_index
            bit_index += 1

    color_grid = bytearray()
    for y in (0, 2, 4, 6):
        for x in (1, 3, 5, 7):
            color_grid.extend(rgb(x, y))
    return f"{bits:016x}", base64.b64encode(color_grid).decode("ascii")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--catalog",
        type=Path,
        default=Path("app/assets/catalog/bsp_catalog.json"),
    )
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=Path(".catalog_cache/bsp/covers"),
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("app/assets/catalog/covers"),
    )
    parser.add_argument("--cwebp", type=Path, required=True)
    parser.add_argument("--dwebp", type=Path, required=True)
    parser.add_argument("--library-path", type=Path)
    parser.add_argument("--quality", type=int, default=72)
    parser.add_argument("--width", type=int, default=240)
    parser.add_argument("--height", type=int, default=320)
    args = parser.parse_args()

    payload = json.loads(args.catalog.read_text(encoding="utf-8"))
    built = 0
    missing: list[str] = []
    for issue in payload["issues"]:
        issue.pop("coverUrl", None)
        edition = str(issue["sourceEdition"]).lower()
        number = int(issue["number"])
        source = args.source_dir / edition / f"{number:04d}.jpg"
        destination = args.output_dir / edition / f"{number:04d}.webp"
        if not source.exists():
            issue["coverAsset"] = None
            issue["visualHash"] = None
            issue["colorSignature"] = None
            missing.append(str(issue["id"]))
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        run(
            [
                str(args.cwebp),
                "-quiet",
                "-resize",
                str(args.width),
                str(args.height),
                "-q",
                str(args.quality),
                "-m",
                "6",
                "-metadata",
                "none",
                str(source),
                "-o",
                str(destination),
            ],
            args.library_path,
        )
        visual_hash, color_signature = visual_signature(
            destination,
            args.dwebp,
            args.library_path,
        )
        issue["coverAsset"] = destination.as_posix().removeprefix("app/")
        issue["visualHash"] = visual_hash
        issue["colorSignature"] = color_signature
        built += 1

    args.catalog.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Built {built} local cover assets")
    if missing:
        print(f"Missing source covers: {', '.join(missing)}")


if __name__ == "__main__":
    main()
