<!-- SPDX-License-Identifier: Apache-2.0 -->
# Next release

This branch (`docs/next-release`) holds page changes for the release after the one in `koinon.ref`.
The main repository made these changes after the tag in `koinon.ref`, and then deleted its copies of
the pages.

The branch is merged in the same pull request that moves `koinon.ref` to the new tag. Do not merge it
before that.

The scripts on this branch already target the next tag. `hack/commands-check.sh` reads the command
files `test/e2e/commands/*.e1`, and `hack/pages-check.sh` runs the page tests of the release with
`KOINON_PAGES_DIR`. So the `commands` check fails until `koinon.ref` moves: the tag in `koinon.ref`
(v0.1.0-rc.11) has neither the command files nor `internal/declarative/pages_test.go`.

The release pull request changes only `koinon.ref`, and deletes this file. It needs a tag that has the
command files, `pages_test.go`, and `hack/docs-e1.sh` with file mode (`E1_FILE`). The workflow file needs no change.

Two links on these pages point at `main`, because the paths they name are not in the old tag:
`docs/dev/prices.md` (default-prices page) and `internal/cmd/koinonapi/settings.go` (secret-keys
page). The link `blob/main/docs/dev/prices.md` fails the link check until the main repository's pull
request stateracloud/koinon#506 is merged. When `koinon.ref` moves, change both links to the new tag.

Pull requests of the main repository (`stateracloud/koinon`) whose page changes this branch carries:

- #486: audit page (`installEventDeferred` in the install-log summary).
- #488: prerequisites page (Agent Sandbox v1.0.10 and its SHA-256).
- #493: restore-hold in the backup-restore, metrics and secret-keys pages (`keys verify`,
  `koinon_restore_hold`, the new `hold`, `verify-keys` and `release` blocks).
- #494: backup-restore, metrics and upgrading pages (the install mark: its Secret, backup, and the
  unmarked-objects gauges).
- #570: backup-restore, metrics and upgrading pages (`koinon-reconciler unmarked list`, the reasons table,
  `koinon_openshell_unmarked_objects_waiting_for_agent`).
- #496: metrics page (`koinon_reconciler_openshell_gateway_id_mismatch`) and sandbox-break-glass page
  (relabelling a sandbox namespace).
- #497: quickstart and backup-restore pages (the commands now come from `test/e2e/commands/*.e1`).

Carried up to main commit ac1b22163.

The merge pull request deletes this file.
