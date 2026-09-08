#!/usr/bin/env python3
"""Install the notify dispatcher, preserving the existing handler and a backup.

This configures notifications; it never sends a test message.
"""

import argparse
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import sys


def install(home, topic):
    config_path = home / "config.toml"
    original = config_path.read_text(encoding="utf-8")
    matches = list(re.finditer(r"^notify\s*=\s*(\[[^\n]*\])\s*$", original, re.MULTILINE))
    # Require a simple top-level JSON-compatible string array; fail safely otherwise.
    if len(matches) != 1 or "[" in original[:matches[0].start()]:
        raise ValueError("Expected one top-level, single-line notify array; no settings changed")
    match = matches[0]
    previous = json.loads(match.group(1))
    if not isinstance(previous, list) or not all(isinstance(item, str) for item in previous):
        raise ValueError("Invalid existing notify command")
    directory = home / "phone-notify"
    settings_path = directory / "settings.json"
    dispatcher = directory / "dispatch.py"
    command = [sys.executable, str(dispatcher), str(settings_path)]
    settings = json.loads(settings_path.read_text()) if settings_path.exists() else {}
    if previous != command:
        if str(dispatcher) in previous:
            raise ValueError("Existing dispatcher uses different arguments; inspect configuration first")
        settings["original_notify"] = previous
    elif "original_notify" not in settings:
        raise ValueError("Original notify handler is missing; no settings changed")
    settings.update(topic=topic, host="https://ntfy.sh", state_dir=str(directory / "state"))
    updated = original[:match.start()] + "notify = " + json.dumps(command) + "\n" + original[match.end():]
    os.umask(0o077)
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    if updated != original:
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        backup = config_path.with_name("config.toml.before-phone-notify-" + stamp)
        shutil.copy2(config_path, backup)
        print("Settings backup:", backup)
    source = Path(__file__).with_name("notify_codex_dispatch.py")
    # Install outside the checkout so changing branches cannot break the hook.
    for target, content in [(dispatcher, source.read_text()),
                            (settings_path, json.dumps(settings, ensure_ascii=False, indent=2) + "\n")]:
        temporary = target.with_suffix(".tmp")
        temporary.write_text(content, encoding="utf-8")
        temporary.replace(target)
    if updated != original:
        temporary = config_path.with_suffix(".phone-notify.tmp")
        temporary.write_text(updated, encoding="utf-8")
        temporary.replace(config_path)
    print("Configured. Restart Codex to ensure the new notify handler is loaded.")
    print("No notification was sent by setup.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--topic", required=True)
    parser.add_argument("--codex-home", type=Path, default=Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))))
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", args.topic):
        parser.error("topic must be 1–64 letters, digits, underscores or hyphens")
    install(args.codex_home.expanduser().resolve(), args.topic)
