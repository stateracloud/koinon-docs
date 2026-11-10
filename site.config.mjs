// SPDX-License-Identifier: Apache-2.0
//
// Site-wide constants. Read by astro.config.mjs, the Banner override and the robots.txt route.

/** The public address of the site. */
export const SITE = 'https://koinon.stateracloud.com'

/** The Koinon release these pages describe. Keep it equal to the one-line file koinon.ref. */
export const KOINON_VERSION = 'v0.1.0-rc.11'

/**
 * The pre-release switch (on by default). While it is on, every page carries a visible banner and a
 * `noindex` robots meta tag, and robots.txt disallows everything. Turn it off at build time with
 * `PRE_RELEASE=false` (for Cloudflare: a build variable) when the maintainer says go.
 */
export const PRE_RELEASE = process.env.PRE_RELEASE !== 'false'
