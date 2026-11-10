#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# The commands on the quickstart and backup-restore pages are the commands the Koinon repository
# tests. A fenced block whose info string is `sh e1=<name>` is one of them. This script checks that
# the blocks on each page equal the blocks of the command file of the Koinon release in `koinon.ref`:
#
#   quickstart page       test/e2e/commands/quickstart.e1
#   backup-restore page   test/e2e/commands/backup-restore.e1
#
# A command file has a comment header, then blocks that each start with a line `# e1=<name>`. The
# file side is read by hack/docs-e1.sh of the release itself (`E1_FILE=<file> docs-e1.sh script`).
# For each page the check requires: the same
# block names in the same order, byte-equal commands (empty lines are not part of a block, as in
# the reader), at least one block on each side, and valid shell in each page block (bash -n). A block
# that is on one side only is a failure.
#
# The Koinon repository owns the commands. When you change a command on purpose, change it there
# first, cut a release, and move koinon.ref to it. This branch needs a release that has the command
# files; earlier releases (v0.1.0-rc.11 and before) keep a golden script and the guide page instead.
#
# Usage:  hack/commands-check.sh
# Env:    KOINON_SRC   a local Koinon checkout or export at the pinned release, for offline runs.
#                      Without it the script fetches the tag of koinon.ref from github.com (shallow,
#                      into a temporary directory).
#         KOINON_REPO  the repository to fetch (default https://github.com/stateracloud/koinon.git)
#         QUICKSTART_PAGE, BACKUP_PAGE  the page files, to check a changed copy

# Needs bash 5 (the same rule as the Koinon repository); keep this line above any bash 4+ syntax.
[ "${BASH_VERSINFO:-0}" -ge 5 ] || { echo "These scripts need bash 5 or newer (this is $BASH_VERSION); on macOS: brew install bash" >&2; exit 2; }

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
quickstart=${QUICKSTART_PAGE:-$root/src/content/docs/docs/start/quickstart.md}
backup=${BACKUP_PAGE:-$root/src/content/docs/docs/operate/backup-restore.md}
# shellcheck source=lib/koinon-src.sh source-path=SCRIPTDIR
. "$root/hack/lib/koinon-src.sh"
ref=$(koinon_ref "$root")

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
ok() { echo "ok: $*"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/commands-check.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

# The command files of the Koinon repository at the pinned release, and the reader of those files,
# hack/docs-e1.sh. The file side is read by that script and by no parser of ours: the end-to-end test
# and this check then read the same bytes, and a change of the format at a later tag cannot make the
# two disagree.
qfile_rel=test/e2e/commands/quickstart.e1
bfile_rel=test/e2e/commands/backup-restore.e1
reader_rel=hack/docs-e1.sh
KOINON_SRC_HINT="; this site needs a Koinon release that has the command files $qfile_rel and $bfile_rel and their reader $reader_rel with file mode (E1_FILE) (v0.1.0-rc.11 and earlier do not): move koinon.ref to a release that has them"
koinon_src "$tmp" "$qfile_rel" "$bfile_rel" "$reader_rel"
src=$KOINON_SRC_DIR
for f in "$quickstart" "$backup"; do
  [[ -f $f ]] || { echo "missing file: $f" >&2; exit 2; }
done
for f in "$qfile_rel" "$bfile_rel" "$reader_rel"; do
  [[ -f $src/$f ]] || { echo "$f does not exist in the Koinon sources at $ref$KOINON_SRC_HINT" >&2; exit 2; }
done
reader=$src/$reader_rel
grep -q 'E1_FILE' "$reader" || { echo "$reader_rel at $ref has no file mode (E1_FILE)$KOINON_SRC_HINT" >&2; exit 2; }

# The page side: this repository's own extraction of the `sh e1=<name>` fences. It prints the form
# of `docs-e1.sh script`: a line "# e1=<name>", then the block's commands (an empty line is dropped).
page_script() { # page_script <page>
  awk '
    /^```/ {
      if (name != "") { name = ""; next }
      if (match($0, /^```(sh|bash) +e1=[a-z0-9-]+/)) {
        s = substr($0, RSTART, RLENGTH); sub(/^.*e1=/, "", s); name = s
        if (name in seen) { print "duplicate e1 block: " name > "/dev/stderr"; exit 2 }
        seen[name] = 1; print "# e1=" name; next
      }
      next
    }
    name != "" && length($0) > 0 { print }
  ' "$1"
}
script_names() { sed -n 's/^# e1=//p' "$1"; }

# compare <label> <page> <command file relative path>
compare() {
  local label=$1 page=$2 rel=$3 key n
  key=$(basename "$rel" .e1)
  page_script "$page" >"$tmp/$key.page" || { fail "reading the e1 blocks of $page"; return; }
  # The reader's own message is shown when it refuses the file (exit code 1 or 2).
  E1_FILE=$src/$rel "$BASH" "$reader" script >"$tmp/$key.file" 2>"$tmp/$key.err" || {
    cat "$tmp/$key.err" >&2
    fail "$reader_rel at $ref cannot read $rel"
    return
  }
  [[ -s $tmp/$key.page ]] || { fail "the $label page has no e1 blocks"; return; }
  [[ -s $tmp/$key.file ]] || { fail "$rel at $ref has no e1 blocks"; return; }
  # Valid shell, block by block, and no empty block on the page.
  for n in $(script_names "$tmp/$key.page"); do
    awk -v n="# e1=$n" '$0 == n { on = 1; next } /^# e1=/ && on { exit } on' "$tmp/$key.page" >"$tmp/$key-$n.sh"
    [[ -s $tmp/$key-$n.sh ]] || { fail "e1 block $n of the $label page is empty"; continue; }
    bash -n "$tmp/$key-$n.sh" || fail "e1 block $n of the $label page is not valid shell"
  done
  # A block on one side only gets its own message; the diff then shows the rest.
  local missing=0
  for n in $(script_names "$tmp/$key.file"); do
    script_names "$tmp/$key.page" | grep -qx -- "$n" || { fail "$rel at $ref has the e1 block '$n', which the $label page does not have"; missing=1; }
  done
  for n in $(script_names "$tmp/$key.page"); do
    script_names "$tmp/$key.file" | grep -qx -- "$n" || { fail "the $label page has the e1 block '$n', which $rel at $ref does not have"; missing=1; }
  done
  if diff -u "$tmp/$key.file" "$tmp/$key.page" >"$tmp/$key.diff"; then
    ok "the $label page's e1 blocks equal $rel at $ref ($(script_names "$tmp/$key.page" | wc -l | tr -d ' ') blocks)"
  else
    cat "$tmp/$key.diff" >&2
    [[ $missing -eq 1 ]] || fail "the $label page's e1 commands differ from $rel at $ref (what the Koinon end-to-end test runs); change the command in the Koinon repository first, then move koinon.ref"
  fi
}

compare quickstart "$quickstart" "$qfile_rel"
compare backup-restore "$backup" "$bfile_rel"

if [[ $failures -ne 0 ]]; then
  echo "commands-check: $failures problem(s)" >&2
  exit 1
fi
echo "commands-check: all checks passed"
