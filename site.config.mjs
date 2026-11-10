// SPDX-License-Identifier: Apache-2.0
//
// Site-wide constants. Read by astro.config.mjs, the Banner override and the robots.txt route.

import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

/** The public address of the site. */
export const SITE = 'https://koinon.stateracloud.com'

/** The Koinon release these pages describe: the one line in the file koinon.ref (the one source of truth; builds run from the repository root). */
export const KOINON_VERSION = readFileSync(resolve(process.cwd(), 'koinon.ref'), 'utf8').trim()
if (!KOINON_VERSION) {
  throw new Error('koinon.ref is empty: it must hold the Koinon release the pages describe, for example v0.1.0')
}

/**
 * The pre-release switch (on by default). While it is on, every page carries a visible banner and a
 * `noindex` robots meta tag, and robots.txt disallows everything. Turn it off at build time with
 * `PRE_RELEASE=false` (for Cloudflare: a build variable) when the maintainer says go.
 */
export const PRE_RELEASE = process.env.PRE_RELEASE !== 'false'
