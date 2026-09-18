# Source this file from ~/.zshrc. Keep the shortcuts with the project backup.
typeset -g _habit_app_root="${${(%):-%x}:A:h:h}"
typeset -g _habit_dev_root="${_habit_app_root%-redesign}"
typeset -g _habit_beta_root="${_habit_dev_root}-redesign"

_habit_run() (
  local flavor="$1" mode="$2" argument
  local project_root="$_habit_dev_root" expected_branch=codex/dev
  shift 2
  if [[ "$flavor" == redesign ]]; then
    project_root="$_habit_beta_root"
    expected_branch=codex/beta
  fi
  for argument in "$@"; do
    case "$argument" in
      --flavor|--flavor=*)
        print -u2 '請用 prod、dev 或 beta 選擇 App，不要另外指定 --flavor。'
        return 2
        ;;
      --debug|--release|--profile)
        print -u2 '模式請使用 prod、dev 或 beta；dev release 僅為相容舊指令。'
        return 2
        ;;
    esac
  done
  if ! command -v flutter >/dev/null 2>&1; then
    print -u2 'Flutter 尚未安裝或未加入 PATH；請先完成 Mac 開發環境設定。'
    return 127
  fi
  cd "$project_root" || return
  if [[ "$(git branch --show-current)" != "$expected_branch" ]]; then
    print -u2 "目前目錄不是 $expected_branch；請先確認版本，避免更新錯誤的 App。"
    return 2
  fi
  print "來源：$PWD ($expected_branch)；模式：$mode；flavor：$flavor"
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

beta() {
  _habit_run redesign release "$@"
}
