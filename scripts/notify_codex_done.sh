#!/usr/bin/env bash
# Codex CLI notify hook -> reuse the ntfy notifier.
# Codex passes one JSON arg, e.g.
#   {"type":"agent-turn-complete","turn-id":"...","last-assistant-message":"..."}
set -u

dir="$(cd "$(dirname "$0")" && pwd)"
payload="${1:-}"

# Try to pull the last assistant message out of the JSON for a nicer body.
msg="Codex 本輪工作完成"
if command -v python3 >/dev/null 2>&1 && [ -n "$payload" ]; then
  parsed="$(printf '%s' "$payload" | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
    print((d.get("last-assistant-message") or "").strip())
except Exception:
    pass
' 2>/dev/null)"
  [ -n "$parsed" ] && msg="$parsed"
fi

AI_NOTIFY_TITLE="habit-app Codex" exec "$dir/notify_ai_done.sh" "$msg"
