<!-- SPDX-License-Identifier: Apache-2.0 -->
# Next release

This branch (`docs/next-release`) holds page changes for the release after the one in `koinon.ref`.
The main repository made these changes after the tag in `koinon.ref`, and then deleted its copies of
the pages.

The branch is merged in the same pull request that moves `koinon.ref` to the new tag. Do not merge it
before that.

`hack/commands-check.sh` cannot pass on this branch. It compares with the tag in `koinon.ref`, and the
new tag does not exist yet.

When `koinon.ref` moves:

- `hack/commands-check.sh` must read `test/e2e/commands/quickstart.e1` and
  `test/e2e/commands/backup-restore.e1` from the main repository. `test/e2e/quickstart.golden.sh` no
  longer exists.
- `hack/pages-check.sh` must set `KOINON_PAGES_DIR` for the manifest tests, in place of the copy
  workaround.

Pull requests of the main repository (`stateracloud/koinon`) whose page changes this branch carries:

- #486: audit page (`installEventDeferred` in the install-log summary).
- #488: prerequisites page (Agent Sandbox v1.0.10 and its SHA-256).
- #493: restore-hold in the backup-restore, metrics and secret-keys pages (`keys verify`,
  `koinon_restore_hold`, the new `hold`, `verify-keys` and `release` blocks).
- #494: backup-restore, metrics and upgrading pages (the install mark: its Secret, backup, and the
  unmarked-objects gauges).
- #496: metrics page (`koinon_reconciler_openshell_gateway_id_mismatch`) and sandbox-break-glass page
  (relabelling a sandbox namespace).
- #497: quickstart and backup-restore pages (the commands now come from `test/e2e/commands/*.e1`).

Carried up to main commit ac1b22163.

The merge pull request deletes this file.
