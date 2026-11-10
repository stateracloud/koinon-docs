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
