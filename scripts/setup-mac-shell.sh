#!/bin/bash
# Restore shell shortcuts after moving the project or reinstalling macOS.
set -eu
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
/bin/zsh -n "$project_dir/scripts/habit-shell.zsh"
python3 - "$project_dir" <<'PY'
import datetime
import pathlib
import shlex
import sys

project = pathlib.Path(sys.argv[1])
stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')

def update(name, contents):
    target = pathlib.Path.home() / name
    begin = '# >>> habit-app Mac setup >>>'
    end = '# <<< habit-app Mac setup <<<'
    old = target.read_text() if target.exists() else ''
    block = begin + '\n' + contents.rstrip() + '\n' + end + '\n'
    if begin in old or end in old:
        if old.count(begin) != 1 or old.count(end) != 1 or old.index(end) < old.index(begin):
            raise SystemExit(f'{target}: unexpected setup markers; leaving file untouched')
        start, finish = old.index(begin), old.index(end) + len(end)
        new = old[:start] + block.rstrip('\n') + old[finish:]
    else:
        new = old + ('\n' if old and not old.endswith('\n') else '') + block
    if new == old:
        print(f'Already configured: {target}')
        return
    if target.exists():
        backup = target.with_name(target.name + '.before-habit-' + stamp)
        backup.write_bytes(target.read_bytes())
        backup.chmod(0o600)
        print(f'Backup: {backup}')
    target.write_text(new)
    print(f'Configured: {target}')

update('.zprofile', '''if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
typeset -U path
path=("$HOME/development/flutter/bin" "$HOME/.local/bin" $path)
export PATH''')
update('.zshrc', 'source ' + shlex.quote(str(project / 'scripts/habit-shell.zsh')))
PY
