# shellcheck shell=bash disable=SC2154
# SPDX-License-Identifier: Apache-2.0
#
# Shared by hack/commands-check.sh and hack/pages-check.sh. Source it; do not run it.
#
# The checks compare the pages with the Koinon repository (stateracloud/koinon) at the release that
# koinon.ref names. This file finds those sources:
#
#   koinon_ref <root>                 prints the tag in <root>/koinon.ref (exits 2 when it is empty)
#   koinon_src <tmp> [file ...]       sets KOINON_SRC_DIR to a directory with the Koinon sources
#
# With KOINON_SRC set, KOINON_SRC_DIR is that directory (an offline run: a checkout or an export at
# the pinned release). Without it, the tag is fetched shallow from KOINON_REPO (default
# https://github.com/stateracloud/koinon.git) into <tmp>/koinon. When files are named, only those
# files are extracted; with none, the whole tree is checked out (the Go test needs all of it).
# Needs the caller's `ref` variable.

koinon_ref() {
  local r
  r=$(tr -d '[:space:]' <"$1/koinon.ref")
  [[ -n $r ]] || { echo "koinon.ref is empty" >&2; exit 2; }
  printf '%s\n' "$r"
}

koinon_src() {
  local tmp=$1 f repo
  shift
  if [[ -n ${KOINON_SRC:-} ]]; then
    KOINON_SRC_DIR=$KOINON_SRC
    echo "using the local Koinon sources in $KOINON_SRC_DIR (pinned release: $ref)"
    return 0
  fi
  KOINON_SRC_DIR=$tmp/koinon
  repo=${KOINON_REPO:-https://github.com/stateracloud/koinon.git}
  git init -q "$KOINON_SRC_DIR"
  git -C "$KOINON_SRC_DIR" fetch -q --depth 1 "$repo" "refs/tags/$ref:refs/tags/$ref" || { echo "cannot fetch $ref from $repo" >&2; exit 2; }
  if [[ $# -eq 0 ]]; then
    git -C "$KOINON_SRC_DIR" -c advice.detachedHead=false checkout -q "refs/tags/$ref" || { echo "cannot check out $ref" >&2; exit 2; }
  else
    for f in "$@"; do
      mkdir -p "$KOINON_SRC_DIR/$(dirname "$f")"
      git -C "$KOINON_SRC_DIR" show "refs/tags/$ref:$f" >"$KOINON_SRC_DIR/$f" || { echo "$f does not exist at $ref" >&2; exit 2; }
    done
  fi
  echo "fetched the Koinon sources at $ref"
}

# Path lists have one line per path: "f<TAB>path" for a file, "d<TAB>path" for a directory.
#
# koinon_main_paths <tmp> <outfile>: writes the path list of the main branch of the Koinon repository
# to <outfile>. With KOINON_MAIN_SRC set (an offline run), the list comes from that checkout or
# export. Otherwise main is fetched shallow, without file contents (a partial clone), and listed
# with git ls-tree.
koinon_main_paths() {
  local tmp=$1 out=$2 repo
  if [[ -n ${KOINON_MAIN_SRC:-} ]]; then
    koinon_list_dir "$KOINON_MAIN_SRC" >"$out"
    return 0
  fi
  repo=${KOINON_REPO:-https://github.com/stateracloud/koinon.git}
  git init -q "$tmp/koinon-main"
  git -C "$tmp/koinon-main" fetch -q --depth 1 --filter=blob:none "$repo" refs/heads/main || { echo "cannot fetch main from $repo" >&2; exit 2; }
  git -C "$tmp/koinon-main" ls-tree -r -t FETCH_HEAD | awk -F'\t' '{ split($1, a, " "); print (a[2] == "tree" ? "d" : "f") "\t" $2 }' >"$out" || { echo "cannot list main" >&2; exit 2; }
}

# koinon_list_dir <dir>: the path list of <dir>. A git work tree lists tracked files and their
# parent directories (so untracked build output cannot make a dead link pass). A plain export is
# listed with find, without .git and node_modules.
koinon_list_dir() {
  if [[ -e $1/.git ]] && git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$1" ls-files | awk '
      { print "f\t" $0
        n = split($0, p, "/"); d = ""
        for (i = 1; i < n; i++) { d = (d == "" ? p[i] : d "/" p[i]); if (!(d in seen)) { seen[d] = 1; print "d\t" d } } }'
  else
    (cd "$1" && {
      find . \( -name .git -o -name node_modules \) -prune -o -type f -print | sed -e 's|^\./||' -e 's|^|f\t|'
      find . \( -name .git -o -name node_modules \) -prune -o -type d -print | sed -e 's|^\./||' -e '/^\.$/d' -e 's|^|d\t|'
    })
  fi
}
