# Source this file from ~/.zshrc. Keep the shortcuts with the project backup.
typeset -g _habit_app_root="${${(%):-%x}:A:h:h}"

_habit_run() (
  local flavor="$1" mode="$2" argument
  shift 2
  for argument in "$@"; do
    case "$argument" in
      --flavor|--flavor=*)
        print -u2 '請用 prod 或 dev 選擇 App，不要另外指定 --flavor。'
        return 2
        ;;
      --debug|--release|--profile)
        print -u2 '模式請使用 prod、dev 或 dev release。'
        return 2
        ;;
    esac
  done
  if ! command -v flutter >/dev/null 2>&1; then
    print -u2 'Flutter 尚未安裝或未加入 PATH；請先完成 Mac 開發環境設定。'
    return 127
  fi
  cd "$_habit_app_root" || return
  flutter run "--$mode" --flavor "$flavor" "$@"
)

prod() {
  _habit_run prod release "$@"
}

dev() {
  local mode=debug
  case "${1:-}" in
    debug|--debug) mode=debug; shift ;;
    release|--release) mode=release; shift ;;
  esac
  _habit_run dev "$mode" "$@"
}
