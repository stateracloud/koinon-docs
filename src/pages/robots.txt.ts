// SPDX-License-Identifier: Apache-2.0
//
// robots.txt follows the pre-release switch (site.config.mjs): disallow everything while it is on.
import type { APIRoute } from 'astro'
import { PRE_RELEASE, SITE } from '../../site.config.mjs'

export const GET: APIRoute = () => {
  const body = PRE_RELEASE
    ? 'User-agent: *\nDisallow: /\n'
    : `User-agent: *\nAllow: /\n\nSitemap: ${SITE}/sitemap-index.xml\n`
  return new Response(body, { headers: { 'Content-Type': 'text/plain; charset=utf-8' } })
}
