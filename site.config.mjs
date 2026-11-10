// SPDX-License-Identifier: Apache-2.0
//
// Site-wide constants. Read by astro.config.mjs, the Banner override and the robots.txt route.

import { readFileSync } from 'node:fs'

/** The public address of the site. */
export const SITE = 'https://koinon.stateracloud.com'

/**
 * The Koinon release these pages describe: the one line in the file koinon.ref (the one source of
 * truth). astro.config.mjs calls this with the file's URL (Astro loads that config unbundled, so
 * import.meta.url is right there) and hands the result to the pages as import.meta.env.KOINON_VERSION.
 */
export function readKoinonVersion(refUrl) {
  const version = readFileSync(refUrl, 'utf8').trim()
  if (!version) {
    throw new Error('koinon.ref is empty: it must hold the Koinon release the pages describe, for example v0.1.0')
  }
  return version
}

/**
 * The pre-release switch (on by default). While it is on, every page carries a visible banner and a
 * `noindex` robots meta tag, and robots.txt disallows everything. Turn it off at build time with
 * `PRE_RELEASE=false` (for Cloudflare: a build variable) when the maintainer says go.
 */
export const PRE_RELEASE = process.env.PRE_RELEASE !== 'false'
