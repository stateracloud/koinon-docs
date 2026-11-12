// SPDX-License-Identifier: Apache-2.0
import { defineCollection } from 'astro:content'
import { docsLoader } from '@astrojs/starlight/loaders'
import { docsSchema } from '@astrojs/starlight/schema'
import { z } from 'astro/zod'

// Document metadata (ADR 0115 of the Koinon repository, docs/dev/doc-metadata.md there). The shape
// is checked here; the area and tag names are checked against the Koinon repository's
// docs/metadata/{areas,tags}.txt by `hack/notion-sync.mjs --emit` in the build job. They are
// optional in the schema because the home and 404 pages carry none; the emit step requires them on
// every page under /docs/.
const kebab = z.string().regex(/^[a-z0-9]+(-[a-z0-9]+)*$/, 'lower-case kebab-case')

export const collections = {
  docs: defineCollection({
    loader: docsLoader(),
    schema: docsSchema({
      extend: z.object({
        area: kebab.optional(),
        tags: z.array(kebab).min(1).max(6).optional(),
        audience: z.array(z.enum(['user', 'operator', 'contributor'])).min(1).optional(),
      }),
    }),
  }),
}
