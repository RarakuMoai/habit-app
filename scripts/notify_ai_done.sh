#!/usr/bin/env bash
# Send an AI work-complete notification via ntfy.

set -u

topic="${NTFY_TOPIC:-habit-tumi-x7k2m9q4}"
host="${NTFY_HOST:-https://ntfy.sh}"
title="${AI_NOTIFY_TITLE:-habit-app AI}"
tags="${AI_NOTIFY_TAGS:-white_check_mark}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --title)
      title="${2:-$title}"
      shift 2
      ;;
    --tags)
      tags="${2:-$tags}"
      shift 2
      ;;
    --topic)
      topic="${2:-$topic}"
      shift 2
      ;;
    --host)
      host="${2:-$host}"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

message="${*:-AI work completed}"

# 穩定不漏訊息：自動重試（含 4xx/5xx/連線錯），失敗才寫 log 方便事後查。
log="${AI_NOTIFY_LOG:-/Users/yayoi991331/habit-app/scripts/.notify_failures.log}"
if ! curl -fsS \
  --retry 4 --retry-delay 2 --retry-all-errors --max-time 10 \
  "${host}/${topic}" \
  -H "Title: ${title}" \
  -H "Tags: ${tags}" \
  -d "${message}" >/dev/null 2>&1; then
  printf '%s\t%s\t%s\n' "$(date '+%F %T')" "${title}" "${message}" >>"$log" 2>/dev/null
  exit 1
fi
