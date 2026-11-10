#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# The commands on the quickstart and backup-restore pages are the commands the Koinon repository
# tests. A fenced block whose info string is `sh e1=<name>` is one of them. This script checks that
# the blocks on the pages equal the ones in stateracloud/koinon at the release in `koinon.ref`:
#
#   1. Every e1 block of the quickstart is valid shell (bash -n), and the blocks, in order, equal
#      test/e2e/quickstart.golden.sh (the commands the end-to-end test runs).
#   2. Every e1 block of the backup-restore page is valid shell, and the blocks, in order, equal the
#      e1 blocks of the guide that test/e2e/backup-restore.sh runs (its GUIDE= line), command for
#      command. test/e2e/backup-restore.sh must also run every block (each `blk <name>` line names one).
#
# The Koinon repository owns the commands (the end-to-end test runs its own command file). When you
# change a command on purpose, change it there first, cut a release, and move koinon.ref to it.
#
# TODO(stateracloud/koinon issue 491): after the cut-over the main repository no longer keeps the
# guide page. The source of the backup-restore commands becomes the main repository's own command
# file, and the guide_rel line below changes to it.
#
# Ported from hack/docs-e1.sh and hack/docs-check.sh (steps 1 and 2b) of stateracloud/koinon at the
# release in koinon.ref.
#
# Usage:  hack/commands-check.sh
# Env:    KOINON_SRC   a local Koinon checkout or export that holds test/e2e/quickstart.golden.sh and
#                      test/e2e/backup-restore.sh at the pinned release, for offline runs. Without it
#                      the script fetches the tag of koinon.ref from github.com (shallow, into a
#                      temporary directory).
#         (it also needs docs/site/src/content/docs/guides/backup-restore.md)
#         KOINON_REPO  the repository to fetch (default https://github.com/stateracloud/koinon.git)
#         QUICKSTART_PAGE, BACKUP_PAGE  the page files, to check a changed copy

# Needs bash 5 (the same rule as the Koinon repository); keep this line above any bash 4+ syntax.
[ "${BASH_VERSINFO:-0}" -ge 5 ] || { echo "These scripts need bash 5 or newer (this is $BASH_VERSION); on macOS: brew install bash" >&2; exit 2; }

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
quickstart=${QUICKSTART_PAGE:-$root/src/content/docs/docs/start/quickstart.md}
backup=${BACKUP_PAGE:-$root/src/content/docs/docs/operate/backup-restore.md}
ref=$(tr -d '[:space:]' <"$root/koinon.ref")
[[ -n $ref ]] || { echo "koinon.ref is empty" >&2; exit 2; }

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
ok() { echo "ok: $*"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/commands-check.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

# The files of the Koinon repository at the pinned release.
golden_rel=test/e2e/quickstart.golden.sh
runner_rel=test/e2e/backup-restore.sh
guide_rel=docs/site/src/content/docs/guides/backup-restore.md
if [[ -n ${KOINON_SRC:-} ]]; then
  src=$KOINON_SRC
  echo "using the local Koinon sources in $src (pinned release: $ref)"
else
  src=$tmp/koinon
  repo=${KOINON_REPO:-https://github.com/stateracloud/koinon.git}
  git init -q "$src"
  git -C "$src" fetch -q --depth 1 "$repo" "refs/tags/$ref:refs/tags/$ref" || { echo "cannot fetch $ref from $repo" >&2; exit 2; }
  for f in "$golden_rel" "$runner_rel" "$guide_rel"; do
    mkdir -p "$src/$(dirname "$f")"
    git -C "$src" show "refs/tags/$ref:$f" >"$src/$f" || { echo "$f does not exist at $ref" >&2; exit 2; }
  done
  echo "fetched the Koinon sources at $ref"
fi
golden=$src/$golden_rel
runner=$src/$runner_rel
guide=$src/$guide_rel
for f in "$quickstart" "$backup" "$golden" "$runner" "$guide"; do
  [[ -f $f ]] || { echo "missing file: $f" >&2; exit 2; }
done

# blocks <page>: "<name>\t<line>" for each command line of each e1 block, in order (docs-e1.sh).
blocks() {
  awk '
    /^```/ {
      if (name != "") { name = ""; next }
      if (match($0, /^```(sh|bash) +e1=[a-z0-9-]+/)) {
        s = substr($0, RSTART, RLENGTH); sub(/^.*e1=/, "", s); name = s
        if (name in seen) { print "duplicate e1 block: " name > "/dev/stderr"; exit 2 }
        seen[name] = 1; print name "\t"; next
      }
      next
    }
    name != "" { print name "\t" $0 }
  ' "$1"
}
names() { blocks "$1" | cut -f1 | uniq; }
show() { # show <page> <name>: one block's commands
  local out
  out=$(blocks "$1" | awk -F'\t' -v n="$2" '$1 == n && NF > 1 && $2 != "" { sub(/^[^\t]*\t/, ""); print }')
  [[ -n $out ]] || { echo "no e1 block named $2 in $1" >&2; return 1; }
  printf '%s\n' "$out"
}
script() { # script <page>: every block under a "# e1=<name>" line (the golden form)
  local n
  for n in $(names "$1"); do
    echo "# e1=$n"
    show "$1" "$n"
  done
}

# 1. The quickstart's e1 blocks.
qnames=$(names "$quickstart") || { fail "reading the e1 blocks of $quickstart"; qnames=""; }
[[ -n $qnames ]] || fail "$quickstart has no e1 blocks"
for n in $qnames; do
  show "$quickstart" "$n" >"$tmp/$n.sh" || { fail "e1 block $n is empty"; continue; }
  bash -n "$tmp/$n.sh" || fail "e1 block $n is not valid shell"
done
# The golden file starts with a four-line header; the rest is the script. Plain files, not process
# substitution: sandboxes (macOS Seatbelt) deny opening /dev/fd/N.
tail -n +5 "$golden" >"$tmp/golden.expected"
if ! script "$quickstart" >"$tmp/golden.actual"; then
  fail "reading the e1 blocks of $quickstart"
elif diff -u "$tmp/golden.expected" "$tmp/golden.actual" >"$tmp/golden.diff"; then
  ok "the quickstart's e1 blocks equal $golden_rel at $ref"
else
  cat "$tmp/golden.diff" >&2
  fail "the quickstart's e1 commands differ from $golden_rel at $ref (what the Koinon end-to-end test runs); change the command in the Koinon repository first, then move koinon.ref"
fi

# 2. The backup-restore page's e1 blocks, and what test/e2e/backup-restore.sh runs.
gnames=$(names "$backup") || { fail "reading the e1 blocks of $backup"; gnames=""; }
[[ -n $gnames ]] || fail "$backup has no e1 blocks"
for n in $gnames; do
  show "$backup" "$n" >"$tmp/guide-$n.sh" || { fail "e1 block $n of the backup page is empty"; continue; }
  bash -n "$tmp/guide-$n.sh" || fail "e1 block $n of the backup page is not valid shell"
done
gused=$(grep -v '^[[:space:]]*#' "$runner" | grep -oE '\bblk [a-z0-9-]+' | awk '{print $NF}' | sort -u)
for n in $gused; do
  grep -qx "$n" <<<"$gnames" || fail "$runner_rel at $ref runs e1 block '$n', which the backup page does not have"
done
for n in $gnames; do
  grep -qx "$n" <<<"$gused" || fail "$runner_rel at $ref does not run e1 block '$n' of the backup page"
done
# The commands themselves: the page and the guide at the pinned release, block by block.
if ! script "$guide" >"$tmp/guide.expected"; then
  fail "reading the e1 blocks of $guide_rel at $ref"
elif ! script "$backup" >"$tmp/guide.actual"; then
  fail "reading the e1 blocks of $backup"
elif diff -u "$tmp/guide.expected" "$tmp/guide.actual" >"$tmp/guide.diff"; then
  ok "the backup-restore page's e1 blocks equal those of $guide_rel at $ref"
else
  cat "$tmp/guide.diff" >&2
  fail "the backup-restore e1 commands differ from $guide_rel at $ref (what the Koinon end-to-end test runs); change the command in the Koinon repository first, then move koinon.ref"
fi
[[ $failures -eq 0 ]] && ok "$runner_rel at $ref runs every e1 block of the backup page: $(tr '\n' ' ' <<<"$gused")"

if [[ $failures -ne 0 ]]; then
  echo "commands-check: $failures problem(s)" >&2
  exit 1
fi
echo "commands-check: all checks passed"
