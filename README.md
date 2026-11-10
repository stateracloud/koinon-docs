<!-- SPDX-License-Identifier: Apache-2.0 -->
# koinon-docs

The source of the Koinon documentation site, <https://koinon.stateracloud.com>. It is an
[Astro Starlight](https://starlight.astro.build) site with the Koinon theme. The code, the
decisions and the issue tracker are in [stateracloud/koinon](https://github.com/stateracloud/koinon).

The pages describe one Koinon release, named in `koinon.ref` (today `v0.1.0-rc.11`). While the
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

## The commands check

The quickstart and the backup-restore page show shell commands in fenced blocks that start with
`sh e1=<name>`. The Koinon repository tests exactly these commands in its end-to-end test, so it owns
them. `hack/commands-check.sh` fetches the Koinon release named in `koinon.ref` and checks that:

- the quickstart's blocks are valid shell and equal the blocks of `test/e2e/commands/quickstart.e1`;
- the backup-restore page's blocks are valid shell and equal the blocks of
  `test/e2e/commands/backup-restore.e1`.

For each page the block names, their order and the commands must be equal. A block on one side only
fails the check, and so does a page or a file with no blocks.

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
installs them with `hack/koinon-pins.sh`). The Go tests of the release read the pages from the
directory in `KOINON_PAGES_DIR`; the script sets it to the pages of this repository and runs the tests
in the release. The check fails when one of the two tests is missing, skipped or failed in the release.
It also requires a `yaml model-provider` block on the quickstart and the models page and a
`yaml mcp-server` block on the MCP servers page. For an offline run, set `KOINON_SRC`
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

## Contributing

Issues go in [stateracloud/koinon](https://github.com/stateracloud/koinon/issues) with the `docs`
label; issues are off in this repository. Sign off every commit (`git commit -s`) and use
Conventional Commits. Every change to `main` goes through a pull request: the four checks must pass,
and the pull request is merged with a merge commit. See [AGENTS.md](AGENTS.md) for the rules.

## Licence

Apache-2.0, see [LICENSE](LICENSE). The Geist fonts are SIL OFL 1.1.
