#!/usr/bin/env python3
"""Validate PNG dimensions and real pixel transparency without third-party packages."""

from __future__ import annotations

import argparse
import json
import struct
import sys
import zlib
from pathlib import Path
from typing import Any


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def _paeth(a: int, b: int, c: int) -> int:
    estimate = a + b - c
    pa = abs(estimate - a)
    pb = abs(estimate - b)
    pc = abs(estimate - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def _unfilter_rows(data: bytes, width: int, height: int, bytes_per_pixel: int) -> list[bytes]:
    stride = width * bytes_per_pixel
    expected = height * (stride + 1)
    if len(data) != expected:
        raise ValueError(f"Unexpected decompressed size: {len(data)}; expected {expected}")

    rows: list[bytes] = []
    previous = bytearray(stride)
    offset = 0
    for _ in range(height):
        filter_type = data[offset]
        offset += 1
        encoded = data[offset : offset + stride]
        offset += stride
        decoded = bytearray(stride)

        for index, value in enumerate(encoded):
            left = decoded[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
            above = previous[index]
            upper_left = previous[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
            if filter_type == 0:
                predictor = 0
            elif filter_type == 1:
                predictor = left
            elif filter_type == 2:
                predictor = above
            elif filter_type == 3:
                predictor = (left + above) // 2
            elif filter_type == 4:
                predictor = _paeth(left, above, upper_left)
            else:
                raise ValueError(f"Unsupported PNG filter type: {filter_type}")
            decoded[index] = (value + predictor) & 0xFF

        rows.append(bytes(decoded))
        previous = decoded
    return rows


def inspect_png(path: Path) -> dict[str, Any]:
    raw = path.read_bytes()
    if not raw.startswith(PNG_SIGNATURE):
        raise ValueError(f"Not a PNG file: {path}")

    offset = len(PNG_SIGNATURE)
    width = height = bit_depth = color_type = interlace = None
    idat = bytearray()
    has_trns = False

    while offset + 12 <= len(raw):
        length = struct.unpack(">I", raw[offset : offset + 4])[0]
        chunk_type = raw[offset + 4 : offset + 8]
        chunk_data = raw[offset + 8 : offset + 8 + length]
        offset += 12 + length
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, _, _, interlace = struct.unpack(
                ">IIBBBBB", chunk_data
            )
        elif chunk_type == b"IDAT":
            idat.extend(chunk_data)
        elif chunk_type == b"tRNS":
            has_trns = True
        elif chunk_type == b"IEND":
            break

    if None in (width, height, bit_depth, color_type, interlace):
        raise ValueError(f"PNG is missing a valid IHDR chunk: {path}")

    has_alpha_channel = color_type in (4, 6) or has_trns
    transparent_pixels: int | None = None
    alpha_min: int | None = None
    alpha_max: int | None = None

    if color_type in (4, 6) and bit_depth in (8, 16) and interlace == 0:
        channels = 2 if color_type == 4 else 4
        bytes_per_sample = bit_depth // 8
        bytes_per_pixel = channels * bytes_per_sample
        rows = _unfilter_rows(
            zlib.decompress(bytes(idat)), width, height, bytes_per_pixel
        )
        alpha_offset = (channels - 1) * bytes_per_sample
        alpha_values: list[int] = []
        for row in rows:
            for pixel_start in range(0, len(row), bytes_per_pixel):
                sample = row[
                    pixel_start + alpha_offset : pixel_start + alpha_offset + bytes_per_sample
                ]
                alpha_values.append(int.from_bytes(sample, "big"))
        opaque_value = (1 << bit_depth) - 1
        transparent_pixels = sum(value < opaque_value for value in alpha_values)
        alpha_min = min(alpha_values)
        alpha_max = max(alpha_values)

    return {
        "path": str(path.resolve()),
        "width": width,
        "height": height,
        "bit_depth": bit_depth,
        "color_type": color_type,
        "interlaced": bool(interlace),
        "has_alpha_channel": has_alpha_channel,
        "transparent_pixels": transparent_pixels,
        "alpha_min": alpha_min,
        "alpha_max": alpha_max,
    }


def validate_png(
    path: Path,
    *,
    require_transparency: bool = False,
    expected_size: tuple[int, int] | None = None,
) -> dict[str, Any]:
    info = inspect_png(path)
    if expected_size and (info["width"], info["height"]) != expected_size:
        raise ValueError(
            f"Unexpected PNG size: {info['width']}x{info['height']}; "
            f"expected {expected_size[0]}x{expected_size[1]}"
        )
    if require_transparency:
        if not info["has_alpha_channel"]:
            raise ValueError("Transparent output has no alpha channel")
        if not info["transparent_pixels"]:
            raise ValueError("Transparent output has no pixels with alpha below fully opaque")
    return info


def _parse_size(value: str) -> tuple[int, int]:
    try:
        width, height = value.lower().split("x", 1)
        return int(width), int(height)
    except (TypeError, ValueError) as exc:
        raise argparse.ArgumentTypeError("size must be WIDTHxHEIGHT") from exc


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file", type=Path)
    parser.add_argument("--require-transparency", action="store_true")
    parser.add_argument("--expect-size", type=_parse_size)
    args = parser.parse_args()
    try:
        info = validate_png(
            args.file,
            require_transparency=args.require_transparency,
            expected_size=args.expect_size,
        )
    except (OSError, ValueError, zlib.error) as exc:
        print(f"PNG validation failed: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(info, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
