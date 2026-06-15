#!/usr/bin/env bash
# Codex CLI notify hook -> reuse the ntfy notifier.
# Codex passes one JSON arg, e.g.
#   {"type":"agent-turn-complete","turn-id":"...","last-assistant-message":"..."}
set -u

dir="$(cd "$(dirname "$0")" && pwd)"
payload="${1:-}"

# Try to pull the last assistant message out of the JSON for a nicer body.
# 通知只要一句摘要：取第一個非空行、壓掉多餘空白、截到 120 字，
# 否則整段多行 markdown 會在手機上變一坨亂碼。
msg="Codex 本輪工作完成"
if command -v python3 >/dev/null 2>&1 && [ -n "$payload" ]; then
  parsed="$(printf '%s' "$payload" | python3 -c '
import json, sys, re
try:
    d = json.load(sys.stdin)
    raw = d.get("last-assistant-message") or d.get("last_assistant_message") or ""
    # 第一個非空行當摘要，內部空白壓成單一空格
    line = next((l.strip() for l in raw.splitlines() if l.strip()), "")
    line = re.sub(r"\s+", " ", line)
    if len(line) > 120:
        line = line[:119].rstrip() + "…"
    print(line)
except Exception:
    pass
' 2>/dev/null)"
  [ -n "$parsed" ] && msg="$parsed"
fi

# 摘要結尾是問號 → 這輪是在問使用者選項，換標題/圖示提醒「需要你」。
case "$msg" in
  *'?'|*'？')
    AI_NOTIFY_TITLE="habit-app Codex（需要你）" \
      exec "$dir/notify_ai_done.sh" --tags speech_balloon "$msg"
    ;;
  *)
    AI_NOTIFY_TITLE="habit-app Codex" exec "$dir/notify_ai_done.sh" "$msg"
    ;;
esac
