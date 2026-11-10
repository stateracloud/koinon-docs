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

## Deploy

Cloudflare builds this repository from GitHub (Workers Builds) and serves `dist/` as static assets.
A merge to `main` deploys to <https://koinon.stateracloud.com>; the address is the custom domain in
`wrangler.jsonc`. Cloudflare also builds a preview of each pull request; the check
`Workers Builds: koinon-docs` on the pull request shows the result.
Nothing in this repository's CI deploys. CI runs four checks: `build`, `commands`, `gitleaks`, `dco`.

## Contributing

Issues go in [stateracloud/koinon](https://github.com/stateracloud/koinon/issues) with the `docs`
label; issues are off in this repository. Sign off every commit (`git commit -s`) and use
Conventional Commits. Every change to `main` goes through a pull request: the four checks must pass,
and the pull request is merged with a merge commit. See [AGENTS.md](AGENTS.md) for the rules.

## Licence

Apache-2.0, see [LICENSE](LICENSE). The Geist fonts are SIL OFL 1.1.
