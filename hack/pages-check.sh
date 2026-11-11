#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Checks that the pages still match the code of the Koinon release in `koinon.ref`. It never talks
# to a cluster and never builds the site (pnpm build does that). Needs bash 5, awk, grep, helm and go.
#
#   1. Every `yaml chart-values` block is valid chart values: helm lint --strict and helm template
#      against the chart of the release.
#   2. Every `yaml model-provider` block (quickstart, models page) and `yaml mcp-server` block (MCP
#      servers page) parses with the Go code of the release (internal/declarative, the tests
#      TestDocumentedSecretsParse and TestDocumentedMCPServerSecretsParse).
#   3. Every bold label in the quickstart's browser steps (sections 3 to 8) is a whole quoted string or
#      a regexp in the release's Playwright spec, web/e2e-real/*.spec.ts.
#   4. The versions on the prerequisites page and the gateway page equal the pins of the release
#      (test/e2e/kind/up.sh, Chart.yaml, internal/preflight, values.yaml, hack/versions.env).
#   5. Every link to github.com/stateracloud/koinon/(blob|tree)/<rev>/<path> in the pages exists:
#      <rev> is the tag of koinon.ref (checked in that release) or main (checked in main). Any other
#      <rev> is a failure. The site build checks internal links only.
#
# Ported from hack/docs-check.sh (steps 3, 3b, 4 and 5) of stateracloud/koinon at the release in
# koinon.ref. The old repository kept the pages in docs/site; they are here now.
#
# Limit of check 2: the Go tests of the release read the pages from hard-coded paths
# (docs/site/src/content/docs/quickstart.md, guides/models.md, guides/mcp-servers.md) and have no
# setting for another place. So the script copies the sources of the release to a temporary
# directory and puts the pages of this repository at those paths. The release has to keep the file
# names and the block markers (yaml model-provider, yaml mcp-server) for this to work.
# TODO(stateracloud/koinon issue 491): ask the Koinon repository for an environment variable for the
# pages directory, or for a pages-parsing tool, and drop the copy.
#
# Usage:  hack/pages-check.sh
# Env:    KOINON_SRC   a local Koinon checkout or export at the pinned release, for offline runs.
#                      Without it the script fetches the tag of koinon.ref from github.com.
#         KOINON_MAIN_SRC  with KOINON_SRC: a checkout or export of main, for check 5. Without it, an
#                      offline run fails check 5, unless PAGES_CHECK_SKIP_MAIN_LINKS=1 (a visible
#                      `skip:` line). CI never sets that variable.
#         KOINON_REPO  the repository to fetch (default https://github.com/stateracloud/koinon.git)
#         PAGES_DIR    the pages (default src/content/docs/docs), to check a changed copy
#         HELM         the helm binary (default helm)

# Needs bash 5 (the same rule as the Koinon repository); keep this line above any bash 4+ syntax.
[ "${BASH_VERSINFO:-0}" -ge 5 ] || { echo "These scripts need bash 5 or newer (this is $BASH_VERSION); on macOS: brew install bash" >&2; exit 2; }

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
pages=${PAGES_DIR:-$root/src/content/docs/docs}
HELM=${HELM:-helm}
# shellcheck source=lib/koinon-src.sh source-path=SCRIPTDIR
. "$root/hack/lib/koinon-src.sh"
ref=$(koinon_ref "$root")

quickstart=$pages/start/quickstart.md
prereq=$pages/start/prerequisites.md
gateway=$pages/operate/gateway-modes.md
models=$pages/operate/models.md
mcp=$pages/operate/mcp-servers.md

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
ok() { echo "ok: $*"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pages-check.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

for f in "$quickstart" "$prereq" "$gateway" "$models" "$mcp"; do
  [[ -f $f ]] || { echo "missing page: $f" >&2; exit 2; }
done
command -v "$HELM" >/dev/null || { echo "helm is not installed" >&2; exit 2; }
command -v go >/dev/null || { echo "go is not installed" >&2; exit 2; }

koinon_src "$tmp"
src=$KOINON_SRC_DIR
for f in charts/koinon/Chart.yaml go.mod; do
  [[ -f $src/$f ]] || { echo "missing file in the Koinon sources: $f" >&2; exit 2; }
done

before=$failures
# 1. Chart values blocks. The block list goes through a file (sandboxes deny process substitution).
find "$pages" -name '*.md' | sort | while IFS= read -r d; do
  awk -v dir="$tmp" -v base="$(basename "$d" .md)" '
    /^```yaml chart-values/ { n++; out = sprintf("%s/%s-%d.yaml", dir, base, n); printf "" > out; inblock = 1; next }
    /^```/ { if (inblock) { close(out); printf "%s%c", out, 0; inblock = 0 } ; next }
    inblock { print > out }
  ' "$d"
done >"$tmp/blocks.list"
i=0
while IFS= read -r -d '' f; do
  i=$((i + 1))
  # A block that is an overlay (it does not choose between openshell.clientTLSSecret and
  # openshell.insecure) is checked as if the base block's choice were made; likewise for
  # openshell.address, which the chart requires.
  tls=(--set openshell.insecure=true)
  if grep -qE 'clientTLSSecret|insecure' "$f"; then tls=(); fi
  if ! grep -qE '^\s+address:' "$f"; then tls+=(--set openshell.address=openshell.openshell.svc:8080); fi
  if "$HELM" lint --strict "$src/charts/koinon" -f "$f" ${tls[@]+"${tls[@]}"} >"$tmp/lint.out" 2>&1 && \
    "$HELM" template koinon "$src/charts/koinon" --namespace koinon -f "$f" ${tls[@]+"${tls[@]}"} >/dev/null 2>"$tmp/tpl.out"; then
    :
  else
    cat "$tmp/lint.out" "$tmp/tpl.out" >&2
    fail "chart-values block $(basename "$f") is not valid chart values for the chart at $ref"
  fi
done <"$tmp/blocks.list"
[[ $i -gt 0 ]] || fail "no chart-values blocks found"
[[ $failures -eq $before ]] && ok "$i chart-values blocks checked with helm lint and template"

# 2. Declarative Secrets shown in the pages. The tests read fixed paths, so run them in a copy.
work=$tmp/work
mkdir -p "$work"
# Copy only what the Go test needs: no .git, node_modules, build output or web/ and docs/ trees.
(cd "$src" && tar --exclude=.git --exclude=node_modules --exclude=dist --exclude=./web --exclude=./docs \
  --exclude=./.claude --exclude=./.codegraph -cf - .) | tar -xf - -C "$work"
site=$work/docs/site/src/content/docs
mkdir -p "$site/guides"
cp "$quickstart" "$site/quickstart.md"
cp "$models" "$site/guides/models.md"
cp "$mcp" "$site/guides/mcp-servers.md"
tests="TestDocumentedSecretsParse TestDocumentedMCPServerSecretsParse"
if [[ ! -f $src/internal/declarative/docs_test.go ]]; then
  fail "internal/declarative/docs_test.go does not exist at $ref: the main repository no longer has the test, so check 2 needs a new source"
else
  (cd "$work" && go test -count=1 -v -run '^(TestDocumentedSecretsParse|TestDocumentedMCPServerSecretsParse)$' ./internal/declarative) >"$tmp/secrets.out" 2>&1 || {
    cat "$tmp/secrets.out" >&2
    fail "a model-provider or mcp-server manifest does not parse with the code at $ref (internal/declarative/docs_test.go)"
  }
  # Only a PASS line counts. The ok line is printed only when every test passed.
  passed=1
  for t in $tests; do
    if grep -qE "^--- PASS: $t( |$)" "$tmp/secrets.out"; then
      continue
    fi
    passed=0
    if grep -qE "^--- SKIP: $t( |$)" "$tmp/secrets.out"; then
      fail "the test $t was skipped at $ref: a skipped test checks nothing, so check 2 needs a new source from the main repository"
    elif grep -qE "^--- FAIL: $t( |$)" "$tmp/secrets.out"; then
      fail "the test $t failed at $ref (see the output above)"
    else
      fail "the test $t was not found at $ref: the main repository no longer has the test, so check 2 needs a new source"
    fi
  done
  [[ $passed -eq 1 ]] && ok "the model-provider and mcp-server manifests in the pages parse with the code at $ref ($tests passed)"
fi

# 3. UI labels.
before=$failures
spec=$(cat "$src"/web/e2e-real/*.spec.ts)
awk '/^## 3\./ {on=1} /^## Changing in v0.1/ {on=0} on' "$quickstart" | { grep -oE '\*\*[^*]+\*\*' || true; } | sort -u | sed -e 's/^\*\*//' -e 's/\*\*$//' >"$tmp/labels"
[[ -s $tmp/labels ]] || fail "no bold UI labels found in the quickstart's browser steps"
while IFS= read -r label; do
  # The label must be a whole quoted string ('Label') or a regexp ( /Label/ ) in the spec.
  grep -qF -e "'$label'" -e "/$label/" <<<"$spec" || fail "the quickstart names '$label', which web/e2e-real/*.spec.ts at $ref does not contain"
done <"$tmp/labels"
[[ $failures -eq $before ]] && ok "$(wc -l <"$tmp/labels" | tr -d ' ') UI labels are in the Playwright spec at $ref"

# 4. Pins.
before=$failures
up=$src/test/e2e/kind/up.sh
pin() { # pin <file> <variable>: the value assigned to a variable
  sed -n "s/^$2=\\(.*\\)\$/\\1/p" "$1" | head -1
}
need() { # need <page> <what> <string>
  [[ -n $3 ]] || { fail "could not read $2"; return; }
  grep -qF -- "$3" "$1" || fail "$1 does not contain $2 ($3)"
}
for v in AS_VERSION AS_SHA256 OS_VERSION OS_DIGEST KNP_VERSION KNP_SHA256 CNPG_VERSION CNPG_SHA256 CNPG_IMAGE_DIGEST; do
  need "$prereq" "$v from up.sh at $ref" "$(pin "$up" "$v")"
done
node=$(pin "$up" NODE_IMAGE)
need "$prereq" "NODE_IMAGE from up.sh" "$node"
need "$prereq" "Kubernetes version of the node image" "$(sed -n 's/.*node:v\([0-9]*\.[0-9]*\)\..*/\1/p' <<<"$node")"
need "$prereq" "kubeVersion floor in Chart.yaml" "$(sed -n 's/^kubeVersion: *">=\([0-9]*\.[0-9]*\)\..*/\1/p' "$src/charts/koinon/Chart.yaml")"
need "$prereq" "agent sandbox version in the preflight" "$(sed -n 's#.*agent-sandbox/releases/download/\(v[0-9.]*\)/.*#\1#p' "$src/internal/preflight/preflight.go" | head -1)"
need "$prereq" "OpenShell version in the preflight" "$(sed -n 's/.*SupportedOpenShellVersions = \[\]string{"\([^"]*\)"}.*/\1/p' "$src/internal/preflight/preflight.go")"
need "$prereq" "Postgres image tag in values.yaml" "$(sed -n 's#.*postgresql:\([0-9][0-9.]*\)-.*#\1#p' "$src/charts/koinon/values.yaml" | head -1)"
need "$prereq" "kind version in hack/versions.env" "$(pin "$src/hack/versions.env" KIND_VERSION)"
need "$prereq" "Helm version in hack/versions.env" "$(pin "$src/hack/versions.env" HELM_VERSION | sed 's/^v//')"
need "$gateway" "agentgateway tag in values.yaml" "$(sed -n 's/^ *tag: \(v1\.[0-9.]*\)$/\1/p' "$src/charts/koinon/values.yaml" | head -1)"
[[ $failures -eq $before ]] && ok "prerequisite versions match the release at $ref"

# 5. Links into the Koinon repository.
before=$failures
links=$tmp/links.list
{
  find "$pages" -type f \( -name '*.md' -o -name '*.mdx' \)
  find "$root/src/content/docs" -maxdepth 1 -type f \( -name '*.md' -o -name '*.mdx' \)
  if [[ -f $root/astro.config.mjs ]]; then echo "$root/astro.config.mjs"; fi
  if [[ -d $root/src/components ]]; then find "$root/src/components" -type f; fi
} | sort -u | while IFS= read -r f; do
  grep -hoE 'https://(github\.com/stateracloud/koinon/(blob|tree)|raw\.githubusercontent\.com/stateracloud/koinon)/[A-Za-z0-9_.-]+/[A-Za-z0-9_./#?=&%-]*' "$f" || true
done | sort -u >"$links"
koinon_list_dir "$src" >"$tmp/tag.paths"
main_ready=1
if [[ -n ${KOINON_SRC:-} && -z ${KOINON_MAIN_SRC:-} ]]; then
  if [[ ${PAGES_CHECK_SKIP_MAIN_LINKS:-} == 1 ]]; then
    echo "skip: links to main are not checked (PAGES_CHECK_SKIP_MAIN_LINKS=1 and no KOINON_MAIN_SRC)"
    main_ready=0
  else
    fail "an offline run needs KOINON_MAIN_SRC (a checkout of main) for the links to main; or set PAGES_CHECK_SKIP_MAIN_LINKS=1 to skip them"
    main_ready=0
  fi
else
  koinon_main_paths "$tmp" "$tmp/main.paths"
fi
ntag=0
nmain=0
nskip=0
punct='[.,;:!?]$'
has_path() { # has_path <list> <f|d> <path>
  grep -qFx -- "$2"$'\t'"$3" "$1"
}
while IFS= read -r url; do
  u=$url
  while [[ $u =~ $punct ]]; do u=${u%?}; done   # a full stop or similar at the end of a sentence
  if [[ $u == https://raw.githubusercontent.com/stateracloud/koinon/* ]]; then
    kind=blob
    rest=${u#https://raw.githubusercontent.com/stateracloud/koinon/}
  else
    rest=${u#https://github.com/stateracloud/koinon/}
    kind=${rest%%/*}
    rest=${rest#*/}
  fi
  rev=${rest%%/*}
  path=${rest#*/}
  path=${path%%[#?]*}
  path=${path%/}
  want=f
  [[ $kind == tree ]] && want=d
  if [[ $rev == "$ref" ]]; then
    list=$tmp/tag.paths; where="at $ref"; ntag=$((ntag + 1))
  elif [[ $rev == main ]]; then
    if [[ $main_ready -eq 0 ]]; then nskip=$((nskip + 1)); continue; fi
    list=$tmp/main.paths; where="on main"; nmain=$((nmain + 1))
  else
    fail "the pages link to revision '$rev', but a link must use main or $ref: $url"
    continue
  fi
  if has_path "$list" "$want" "$path"; then
    :
  elif has_path "$list" f "$path" || has_path "$list" d "$path"; then
    fail "the pages link to $path $where with '$kind', but it is a $([[ $want == f ]] && echo directory || echo file): $url"
  else
    fail "the pages link to $path $where, which does not exist: $url"
  fi
done <"$links"
[[ -s $links ]] || fail "no links into the Koinon repository found in the pages"
[[ $failures -eq $before ]] && ok "repository links resolve ($ntag at $ref, $nmain on main, $nskip skipped)"

if [[ $failures -ne 0 ]]; then
  echo "pages-check: $failures problem(s)" >&2
  exit 1
fi
echo "pages-check: all checks passed"
