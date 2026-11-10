#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Prints the tool versions the Koinon release in koinon.ref pins, as `name=value` lines that a
# workflow step can append to $GITHUB_OUTPUT:
#
#   go=<version of go.mod>
#   helm=<HELM_VERSION of hack/versions.env>
#
# CI uses them to install the same Go and Helm that the Koinon repository uses, before
# hack/pages-check.sh runs. Env: KOINON_SRC and KOINON_REPO, as for hack/commands-check.sh.

# Needs bash 5 (the same rule as the Koinon repository); keep this line above any bash 4+ syntax.
[ "${BASH_VERSINFO:-0}" -ge 5 ] || { echo "These scripts need bash 5 or newer (this is $BASH_VERSION); on macOS: brew install bash" >&2; exit 2; }

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/koinon-src.sh source-path=SCRIPTDIR
. "$root/hack/lib/koinon-src.sh"
ref=$(koinon_ref "$root")

tmp=$(mktemp -d "${TMPDIR:-/tmp}/koinon-pins.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

koinon_src "$tmp" go.mod hack/versions.env >&2
go=$(sed -n 's/^go \([0-9][0-9.]*\)$/\1/p' "$KOINON_SRC_DIR/go.mod" | head -1)
helm=$(sed -n 's/^HELM_VERSION=\(.*\)$/\1/p' "$KOINON_SRC_DIR/hack/versions.env" | head -1)
[[ -n $go ]] || { echo "no go version in go.mod at $ref" >&2; exit 2; }
[[ -n $helm ]] || { echo "no HELM_VERSION in hack/versions.env at $ref" >&2; exit 2; }
echo "go=$go"
echo "helm=$helm"
