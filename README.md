<!-- SPDX-License-Identifier: Apache-2.0 -->
# koinon-docs

The source of the Koinon documentation site, <https://koinon.stateracloud.com>. It is an
[Astro Starlight](https://starlight.astro.build) site with the Koinon theme. The code, the
decisions and the issue tracker are in [stateracloud/koinon](https://github.com/stateracloud/koinon).

The pages describe one Koinon release, named in `koinon.ref` (today `v0.1.0-rc.13`). While the
site is pre-release, every page carries a banner and a `noindex` tag, and `robots.txt` disallows all
(`PRE_RELEASE` in `site.config.mjs`).

## Run and build

You need Node (see `.node-version`) and pnpm (see `packageManager` in `package.json`).

```sh
pnpm install --frozen-lockfile
pnpm dev      # http://localhost:4321
pnpm build    # writes dist/; fails on a broken internal link
```

`PRE_RELEASE=false pnpm build` builds the site as it will be after the pre-release label is lifted.

## Layout

| Path | Contents |
| --- | --- |
| `src/content/docs/index.mdx` | the home page (`/`) |
| `src/content/docs/docs/` | all documentation, under `/docs/`: `start`, `operate`, `use`, `contribute` |
| `src/styles/koinon.css` | the Koinon theme (colours, fonts) mapped onto Starlight |
| `src/components/` | the pre-release banner and the top bar link |
| `astro.config.mjs` | site address, sidebar, plugins (links validator, `llms.txt`) |
| `wrangler.jsonc` | the Cloudflare Worker `koinon-docs`: static assets only, no Worker code |
| `hack/commands-check.sh` | the commands check (below) |
| `hack/pages-check.sh` | the pages check (below) |
| `hack/koinon-pins.sh` | prints the Go and Helm versions that the pinned release uses (CI installs them) |
| `hack/lib/koinon-src.sh` | how both checks find the Koinon sources |
| `hack/notion-sync.mjs` | the Notion copy (below) |

## The commands check

The quickstart and the backup-restore page show shell commands in fenced blocks that start with
`sh e1=<name>`. The Koinon repository tests exactly these commands in its end-to-end test, so it owns
them. `hack/commands-check.sh` fetches the Koinon release named in `koinon.ref` and checks that:

- the quickstart's blocks are valid shell and equal `test/e2e/quickstart.golden.sh`;
- the backup-restore page's blocks are valid shell, equal command for command the blocks of the guide
  that `test/e2e/backup-restore.sh` runs, and are exactly the blocks that script runs by name.

To change a command, change it in the Koinon repository, cut a release, then move `koinon.ref` and the
page together. Run the check with bash 5 (`brew install bash` on macOS). For an offline run, set
`KOINON_SRC` to a Koinon checkout or export at the pinned release.

## The pages check

`hack/pages-check.sh` checks the pages against the same Koinon release. It checks that:

- each `yaml chart-values` block passes `helm lint --strict` and `helm template` with the chart of the release;
- each `yaml model-provider` block and each `yaml mcp-server` block parses with the Go code of the
  release;
- each bold label in the quickstart's browser steps is in the release's Playwright spec;
- the versions on the prerequisites page and the gateway page equal the pins of the release;
- each link to `github.com/stateracloud/koinon/blob/<rev>/<path>` or `tree/<rev>/<path>` (and
  `raw.githubusercontent.com/stateracloud/koinon/<rev>/<path>`) points to a path that exists. `blob`
  must be a file and `tree` a directory. A full stop at the end of a link is ignored. `<rev>` must be `main` (checked in a fresh fetch of main) or the tag in
  `koinon.ref` (checked in the release). Any other `<rev>` fails. The site build checks internal
  links only.

It needs bash 5, helm and Go (the versions in `go.mod` and `hack/versions.env` of the release; CI
installs them with `hack/koinon-pins.sh`). The Go test of the release reads the pages from fixed paths
under `docs/site/`, so the script runs it in a temporary copy of the release, with the pages of this
repository put at those paths. The check fails when one of the two tests is missing, skipped or failed in the release
(the Koinon repository then has to give the check a new source). For an offline run, set `KOINON_SRC`
as for the commands check, and `KOINON_MAIN_SRC` to a checkout or export of main for the links to
main. Without `KOINON_MAIN_SRC`, an offline run fails; `PAGES_CHECK_SKIP_MAIN_LINKS=1` skips those
links and prints a `skip:` line. CI must never set it. Set `PAGES_DIR` to check a changed copy of the
pages.

## Deploy

Cloudflare builds this repository from GitHub (Workers Builds) and serves `dist/` as static assets.
A merge to `main` deploys to <https://koinon.stateracloud.com>; the address is the custom domain in
`wrangler.jsonc`. Cloudflare also builds a preview of each pull request; the check
`Workers Builds: koinon-docs` on the pull request shows the result. Cloudflare adds no comment
with the address. The preview is at `https://<branch>-koinon-docs.stateracloud.workers.dev`, where
`<branch>` is the branch name with each `/` changed to `-`. It goes away with the branch.
Nothing in this repository's CI deploys. CI runs four checks: `build`, `commands` (both scripts), `gitleaks`, `dco`.
The separate workflow `notion-sync` is not a check (see Notion copy).

## Notion copy

`hack/notion-sync.mjs` copies the docs into three Notion databases: **Platform Docs** (the pages of
this repository), **ADRs** (`docs/adr` of the Koinon repository at main) and **Research**
(`docs/research` and `docs/spikes` there). Git stays the source of truth. A run rewrites each page
whose source changed (the `Hash` property holds the source's sha256; `Path` is the key) and archives
a page whose source is gone. Relative links become links to GitHub at main, and `/docs/` links
become links to the site. The workflow `notion-sync` runs it after a merge to `main`, every day at
04:17 UTC, and by hand (`force` rewrites every page). `build` runs `--emit`, which converts every
page without touching Notion.

Setup, once:

1. In Notion, create an internal integration (Settings, Connections, Develop or manage
   integrations) with the capabilities Read, Update and Insert content. Open the **Koinon** page,
   then Connections, and add the integration. The databases below that page inherit it.
2. In this repository, add the secret `NOTION_TOKEN` (the integration's token) and the variables
   `NOTION_DS_PLATFORM`, `NOTION_DS_ADRS` and `NOTION_DS_RESEARCH`, each set to the ID of its
   database's data source (Notion: the database's menu, "Manage data sources", "Copy data source ID").
   Without them, the workflow skips.

Each database needs these properties: `Title` (title), `Path`, `Hash` (text), `Source` (URL),
`Synced` (date), `Area` (select) and `Tags` (multi-select). ADRs also need `Number` (number), `State`
(select: Proposed, Accepted, Superseded, Deprecated, Rejected, Other), `Status` (text) and `Date`
(date). Research needs `Kind` (select: Research, Spike), `Stage` (select: Draft, Complete,
Abandoned, Superseded), `Status` (text) and `Date` (date). Platform Docs needs `Section` (select:
Overview, Start, Use, Operate), `Description` (text) and `Audience` (multi-select).

## Page metadata

Every page under `src/content/docs/docs/` has, besides `title`, a `description`, an `area`, one to
six `tags` and an `audience` (`user`, `operator`, `contributor`) in its frontmatter. The areas and
tags are the Koinon repository's (`docs/metadata/areas.txt`, `docs/metadata/tags.txt`, ADR 0115;
how to choose: its `docs/dev/doc-metadata.md`). `src/content.config.ts` checks the shape at build
time, and `hack/notion-sync.mjs --emit` in the `build` job checks the names against the Koinon
repository at main. A new tag lands there first.

Run it locally with the same variables: `node hack/notion-sync.mjs --dry-run` lists what would
change, and `KOINON_MAIN_SRC=<checkout of koinon at main>` skips the fetch.

## Contributing

Issues go in [stateracloud/koinon](https://github.com/stateracloud/koinon/issues) with the `docs`
label; issues are off in this repository. Sign off every commit (`git commit -s`) and use
Conventional Commits. Every change to `main` goes through a pull request: the four checks must pass,
and the pull request is merged with a merge commit. See [AGENTS.md](AGENTS.md) for the rules.

## Licence

Apache-2.0, see [LICENSE](LICENSE). The Geist fonts are SIL OFL 1.1.
