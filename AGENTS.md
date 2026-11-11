<!-- SPDX-License-Identifier: Apache-2.0 -->
# AGENTS.md

Instructions for coding agents working on the Koinon documentation site. The code and the issue
tracker are in [stateracloud/koinon](https://github.com/stateracloud/koinon).

## Commands

- Install: `pnpm install --frozen-lockfile` (pnpm and Node versions: `package.json`, `.node-version`).
- Dev server: `pnpm dev`. Build: `pnpm build` (the build fails on a broken internal link).
- Commands check: `hack/commands-check.sh` (bash 5). Offline: `KOINON_SRC=<koinon checkout or export>`.
- Notion copy: `hack/notion-sync.mjs` (setup: README.md, "Notion copy"). Offline: `--emit <dir>` with
  `KOINON_MAIN_SRC=<koinon checkout at main>`. Git is the source; never edit the Notion pages.
- Pages check: `hack/pages-check.sh` (bash 5, helm, Go). Offline: `KOINON_SRC` and
  `KOINON_MAIN_SRC` (CI never sets `PAGES_CHECK_SKIP_MAIN_LINKS`). It runs in the `commands` job.
  Chart values, manifests, UI labels, versions and links into the Koinon repository must match the release.
- Before you push: `gitleaks git --redact --no-banner --log-opts="origin/main..HEAD" .`

## Rules

- Light rules: a pull request with four checks (`build`, `commands`, `gitleaks`, `dco`), signed-off
  commits (`git commit -s`, Conventional Commits), a merge commit. No claim locks, no merge queue.
- One tracker: issues go in `stateracloud/koinon` (label `docs`). Issues here are off. A docs pull
  request says `Closes stateracloud/koinon#N`.
- Page text comes from the Koinon release in `koinon.ref`. Change a page to match what the release
  does; do not describe what main does.
- **The `e1` block rule.** A fenced block that starts with `sh e1=<name>` on the quickstart and
  backup-restore pages is a command the Koinon repository tests. Never edit one here. Change the
  command in `stateracloud/koinon` (its `test/e2e/quickstart.golden.sh` and the backup-restore guide
  that `test/e2e/backup-restore.sh` runs), release, then move `koinon.ref` and the page.
  `hack/commands-check.sh` compares the commands, not only the block names.
- **Dependencies are at least 3 days old** before they enter the tree (ADR 0079 of the Koinon
  repository; `pnpm-workspace.yaml` enforces it for direct and transitive packages). Pin every
  version exactly, no caret. Starlight is pre-1.0: bump it on its own, with a build.
- **Pre-release switch.** `PRE_RELEASE` in `site.config.mjs` (env var `PRE_RELEASE=false` turns it
  off). On: a banner on every page, a `noindex` meta tag, `robots.txt` disallows all. Do not turn it
  off without the maintainer's go.
- Pages live in `src/content/docs/docs/{start,operate,use}`; the sidebar is in `astro.config.mjs`.
  Internal links are absolute (`/docs/operate/models/`), never relative.
- Theme: `src/styles/koinon.css` maps the Koinon design tokens onto Starlight. Purple is for actions
  and links only. Fonts are self-hosted (fontsource); no request to an external host, no analytics.
  The mascot Tess appears on the 404 page only.
- Every source file you write (config, script, CSS, workflow) starts with
  `SPDX-License-Identifier: Apache-2.0` in a comment.
- No secrets, ever. Fake secrets in examples look fake (`koinon_test_not-a-real-token`).
- Scripts: bash 5, `bash` or direct, `/bin/ls` not an alias, no pagers, no prompts.
