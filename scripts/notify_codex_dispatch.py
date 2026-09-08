#!/usr/bin/env python3
"""Preserve Codex's existing notify handler and send generic ntfy stop alerts.

Invoked by Codex only: python3 notify_codex_dispatch.py CONFIG EVENT_JSON
No conversation content is sent to ntfy. Uses only the Python standard library.
"""

import concurrent.futures
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.error
import urllib.request


def log(state, message):
    # Log fixed diagnostics only; never the event or response body.
    with (state / "notify.log").open("a", encoding="utf-8") as stream:
        stream.write(time.strftime("%Y-%m-%d %H:%M:%S ") + message + "\n")


def forward_native(command, payload, state):
    if not command:
        return
    try:
        result = subprocess.run(
            command + [payload], timeout=15,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        if result.returncode:
            log(state, "existing handler exit=" + str(result.returncode))
    except (OSError, subprocess.TimeoutExpired):
        log(state, "existing handler failed or timed out")


def publish(config, state):
    body = json.dumps({
        "topic": config["topic"],
        "title": "Codex 本輪已停止",
        "message": "請回 Codex 查看結果；本輪可能已完成，或需要你回覆。",
        "tags": ["computer"],
        "priority": 3,
    }, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        config.get("host", "https://ntfy.sh").rstrip("/") + "/",
        data=body, headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=8) as response:
                if 200 <= response.status < 300:
                    return True
                log(state, "unexpected HTTP status=" + str(response.status))
                return False
        except urllib.error.HTTPError as error:
            if error.code != 429 and not 500 <= error.code < 600:
                log(state, "ntfy rejected HTTP=" + str(error.code))
                return False
        except (urllib.error.URLError, TimeoutError, OSError):
            pass
        if attempt < 2:
            time.sleep(2 ** attempt)
    log(state, "ntfy delivery unconfirmed after 3 attempts")
    return False


def notify_phone(config, payload, state):
    try:
        event = json.loads(payload)
    except (ValueError, TypeError):
        return
    if not isinstance(event, dict) or event.get("type") != "agent-turn-complete":
        return
    thread = event.get("thread-id")
    turn = event.get("turn-id")
    if not isinstance(thread, str) or not thread or not isinstance(turn, str) or not turn:
        log(state, "completion event missing thread-id or turn-id; skipped")
        return
    key = hashlib.sha256(json.dumps([thread, turn]).encode()).hexdigest()
    # Serialize duplicate events across processes. Mark only after HTTP success.
    with (state / (key + ".lock")).open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        receipt = state / (key + ".sent")
        if receipt.exists():
            return
        if publish(config, state):
            receipt.touch(mode=0o600)
            log(state, "ntfy accepted completion " + key[:12])


def main():
    if len(sys.argv) != 3:
        return 2
    config_path = Path(sys.argv[1]).expanduser()
    config = json.loads(config_path.read_text(encoding="utf-8"))
    state = Path(config["state_dir"]).expanduser()
    os.umask(0o077)
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    # A stalled network request must not delay the original computer-use handler.
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        native = pool.submit(forward_native, config.get("original_notify", []), sys.argv[2], state)
        try:
            notify_phone(config, sys.argv[2], state)
        except Exception:
            log(state, "phone handler failed; check local configuration")
        native.result()
    return 0


if __name__ == "__main__":
    sys.exit(main())
