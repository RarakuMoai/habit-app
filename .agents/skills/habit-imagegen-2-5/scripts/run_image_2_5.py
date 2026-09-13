#!/usr/bin/env python3
"""Run habit-app image generation through a fixed GPT Image 2.5 configuration."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import mimetypes
import os
import sys
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from verify_png import inspect_png, validate_png


MODEL = "gpt-image-2.5-sunburst"
QUALITY = "max"
OUTPUT_FORMAT = "png"
ALLOWED_SIZES = ("1024x1024", "1024x1536", "1536x1024", "auto")
API_ROOT = "https://api.openai.com/v1"
EDIT_GUARDRAIL = (
    "Image 1 is the edit target. Do not redraw the whole image. Local edit only. "
    "不重繪，只局部修改。 Preserve every unrequested area and the original canvas."
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _read_prompt(args: argparse.Namespace) -> str:
    if args.prompt_file:
        return args.prompt_file.read_text(encoding="utf-8").strip()
    return args.prompt.strip()


def _expected_size(size: str) -> tuple[int, int] | None:
    if size == "auto":
        return None
    width, height = size.split("x", 1)
    return int(width), int(height)


def _source_record(path: Path, role: str) -> dict[str, str]:
    return {
        "role": role,
        "path": str(path.resolve()),
        "sha256": _sha256(path),
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="mode", required=True)

    def add_common(subparser: argparse.ArgumentParser) -> None:
        prompt = subparser.add_mutually_exclusive_group(required=True)
        prompt.add_argument("--prompt")
        prompt.add_argument("--prompt-file", type=Path)
        subparser.add_argument("--size", choices=ALLOWED_SIZES, default="1024x1024")
        subparser.add_argument(
            "--background", choices=("opaque", "transparent"), required=True
        )
        subparser.add_argument("--out", required=True, type=Path)
        subparser.add_argument("--dry-run", action="store_true")

    generate = subparsers.add_parser("generate", help="Create a new image")
    add_common(generate)

    edit = subparsers.add_parser("edit", help="Edit an existing image")
    add_common(edit)
    edit.add_argument("--image", action="append", required=True, type=Path)
    edit.add_argument("--mask", type=Path)
    return parser


def _validate_inputs(args: argparse.Namespace) -> None:
    if args.prompt_file and not args.prompt_file.is_file():
        raise ValueError(f"Prompt file not found: {args.prompt_file}")
    if args.out.suffix.lower() != ".png":
        raise ValueError("Output path must end in .png")
    if args.out.exists() and not args.dry_run:
        raise ValueError(f"Refusing to overwrite existing output: {args.out}")

    if args.mode == "edit":
        for image in args.image:
            if not image.is_file():
                raise ValueError(f"Input image not found: {image}")
        if args.image[0].suffix.lower() != ".png":
            raise ValueError("Image 1, the edit target, must be a PNG")

        target_info = inspect_png(args.image[0])
        if args.mask:
            if not args.mask.is_file():
                raise ValueError(f"Mask file not found: {args.mask}")
            mask_info = validate_png(args.mask, require_transparency=True)
            if (mask_info["width"], mask_info["height"]) != (
                target_info["width"],
                target_info["height"],
            ):
                raise ValueError("Mask and Image 1 must have identical dimensions")

    if not args.dry_run and not os.environ.get("OPENAI_API_KEY"):
        raise ValueError(
            "OPENAI_API_KEY is not set. Set it locally; never paste the key into chat."
        )


def _effective_prompt(args: argparse.Namespace, prompt: str) -> str:
    if args.mode == "edit":
        return f"{EDIT_GUARDRAIL}\n\n{prompt}"
    return prompt


def _request_fields(args: argparse.Namespace, prompt: str) -> dict[str, Any]:
    return {
        "model": MODEL,
        "prompt": prompt,
        "n": 1,
        "size": args.size,
        "quality": QUALITY,
        "background": args.background,
        "output_format": OUTPUT_FORMAT,
    }


def _multipart_body(
    fields: dict[str, Any], images: list[Path], mask: Path | None
) -> tuple[bytes, str]:
    boundary = f"----habit-image-2-5-{uuid.uuid4().hex}"
    chunks: list[bytes] = []

    def append(value: bytes) -> None:
        chunks.append(value)

    for name, value in fields.items():
        append(f"--{boundary}\r\n".encode())
        append(f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode())
        append(str(value).encode("utf-8"))
        append(b"\r\n")

    def append_file(field_name: str, path: Path) -> None:
        filename = path.name.replace('"', "_")
        mime = mimetypes.guess_type(filename)[0] or "application/octet-stream"
        append(f"--{boundary}\r\n".encode())
        append(
            f'Content-Disposition: form-data; name="{field_name}"; '
            f'filename="{filename}"\r\n'.encode()
        )
        append(f"Content-Type: {mime}\r\n\r\n".encode())
        append(path.read_bytes())
        append(b"\r\n")

    for image in images:
        append_file("image[]", image)
    if mask:
        append_file("mask", mask)
    append(f"--{boundary}--\r\n".encode())
    return b"".join(chunks), boundary


def _send_request(args: argparse.Namespace, fields: dict[str, Any]) -> tuple[dict, dict]:
    api_key = os.environ["OPENAI_API_KEY"]
    endpoint = (
        f"{API_ROOT}/images/generations"
        if args.mode == "generate"
        else f"{API_ROOT}/images/edits"
    )
    headers = {"Authorization": f"Bearer {api_key}"}
    if args.mode == "generate":
        body = json.dumps(fields).encode("utf-8")
        headers["Content-Type"] = "application/json"
    else:
        body, boundary = _multipart_body(fields, args.image, args.mask)
        headers["Content-Type"] = f"multipart/form-data; boundary={boundary}"

    request = urllib.request.Request(endpoint, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            response_body = response.read()
            response_meta = {
                "request_id": response.headers.get("x-request-id"),
                "processing_ms": response.headers.get("openai-processing-ms"),
            }
    except urllib.error.HTTPError as exc:
        response_body = exc.read()
        request_id = exc.headers.get("x-request-id") if exc.headers else None
        try:
            error = json.loads(response_body).get("error", {})
            message = error.get("message") or error.get("code") or "unknown API error"
        except (UnicodeDecodeError, json.JSONDecodeError):
            message = "unreadable API error response"
        raise RuntimeError(
            f"Image API returned HTTP {exc.code}: {message}; request_id={request_id}"
        ) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Image API connection failed: {exc.reason}") from exc

    try:
        payload = json.loads(response_body)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeError("Image API returned invalid JSON") from exc
    return payload, response_meta


def _save_api_image(payload: dict, out: Path) -> None:
    try:
        encoded = payload["data"][0]["b64_json"]
        image_bytes = base64.b64decode(encoded, validate=True)
    except (KeyError, IndexError, TypeError, ValueError) as exc:
        raise RuntimeError("Image API response did not contain a valid base64 image") from exc
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(image_bytes)


def _write_provenance(
    args: argparse.Namespace,
    prompt: str,
    validation: dict,
    api_response: dict,
    response_meta: dict,
) -> Path:
    sources: list[dict[str, str]] = []
    if args.mode == "edit":
        for index, image in enumerate(args.image):
            role = "edit_target" if index == 0 else "reference"
            sources.append(_source_record(image, role))
        if args.mask:
            sources.append(_source_record(args.mask, "mask"))

    record = {
        "schema_version": 1,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "endpoint": "/v1/images/generations"
        if args.mode == "generate"
        else "/v1/images/edits",
        "model_requested": MODEL,
        "quality_requested": QUALITY,
        "size_requested": args.size,
        "background_requested": args.background,
        "output_format_requested": OUTPUT_FORMAT,
        "prompt": prompt,
        "prompt_sha256": hashlib.sha256(prompt.encode("utf-8")).hexdigest(),
        "sources": sources,
        "output": {
            "path": str(args.out.resolve()),
            "sha256": _sha256(args.out),
            **validation,
        },
        "api_response": {
            "created": api_response.get("created"),
            "background": api_response.get("background"),
            "output_format": api_response.get("output_format"),
            "quality": api_response.get("quality"),
            "size": api_response.get("size"),
            "usage": api_response.get("usage"),
            **response_meta,
        },
    }
    provenance = args.out.with_suffix(args.out.suffix + ".generation.json")
    provenance.write_text(
        json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return provenance


def main() -> int:
    parser = _build_parser()
    args = parser.parse_args()
    try:
        _validate_inputs(args)
        prompt = _read_prompt(args)
        if not prompt:
            raise ValueError("Prompt must not be empty")
        effective_prompt = _effective_prompt(args, prompt)
        fields = _request_fields(args, effective_prompt)
        if args.dry_run:
            preview = {
                "endpoint": "/v1/images/generations"
                if args.mode == "generate"
                else "/v1/images/edits",
                "output": str(args.out),
                **fields,
            }
            if args.mode == "edit":
                preview["image"] = [str(path) for path in args.image]
                preview["mask"] = str(args.mask) if args.mask else None
            print(json.dumps(preview, ensure_ascii=False, indent=2))
            return 0

        api_response, response_meta = _send_request(args, fields)
        _save_api_image(api_response, args.out)
        validation = validate_png(
            args.out,
            require_transparency=args.background == "transparent",
            expected_size=_expected_size(args.size),
        )
        provenance = _write_provenance(
            args, effective_prompt, validation, api_response, response_meta
        )
        print(f"Validated output: {args.out}")
        print(f"Provenance: {provenance}")
        return 0
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"Image 2.5 workflow failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
