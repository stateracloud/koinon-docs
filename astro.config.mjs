// SPDX-License-Identifier: Apache-2.0
import { defineConfig, passthroughImageService } from 'astro/config'
import starlight from '@astrojs/starlight'
import starlightLinksValidator from 'starlight-links-validator'
import starlightLlmsTxt from 'starlight-llms-txt'
import { PRE_RELEASE, SITE } from './site.config.mjs'

// No analytics. No external fonts (Geist is self-hosted, see src/styles/koinon.css). No deploy from
// this repository's CI: Cloudflare builds from GitHub itself.
export default defineConfig({
  site: SITE,
  // Only the logo, favicon and mascot SVGs go through the image pipeline; they need no resizing, so
  // skip sharp (a native dependency) and keep the install small.
  image: { service: passthroughImageService() },
  integrations: [
    starlight({
      title: 'Koinon',
      description: 'Install Koinon, connect GitHub and run your first agent.',
      logo: {
        light: './src/assets/koinon-mark-light.svg',
        dark: './src/assets/koinon-mark-dark.svg',
        alt: 'Koinon',
      },
      favicon: '/favicon.svg',
      social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/stateracloud/koinon' }],
      editLink: { baseUrl: 'https://github.com/stateracloud/koinon-docs/edit/main/' },
      customCss: ['./src/styles/koinon.css'],
      components: {
        Banner: './src/components/Banner.astro',
        SiteTitle: './src/components/SiteTitle.astro',
        SocialIcons: './src/components/SocialIcons.astro',
      },
      // The pre-release switch (site.config.mjs): tell search engines not to list any page.
      head: PRE_RELEASE ? [{ tag: 'meta', attrs: { name: 'robots', content: 'noindex, nofollow' } }] : [],
      plugins: [
        // The quickstart shows http://localhost:8080 for the reader's own machine: not a broken link.
        starlightLinksValidator({ errorOnLocalLinks: false }),
        starlightLlmsTxt({
          projectName: 'Koinon',
          description:
            'Koinon is an open source org-and-work layer for AI agents on Kubernetes. These pages cover installing, operating and using it.',
        }),
      ],
      sidebar: [
        { label: 'Start here', items: [{ label: 'What is Koinon', slug: 'docs' }, 'docs/start/prerequisites', 'docs/start/quickstart'] },
        {
          label: 'Install and operate',
          items: [
            'docs/operate/models',
            'docs/operate/prices',
            'docs/operate/budgets',
            'docs/operate/mcp-servers',
            'docs/operate/github-app',
            'docs/operate/ghes',
            'docs/operate/gitea',
            'docs/operate/oidc',
            'docs/operate/gateway-modes',
            'docs/operate/agent-health',
            'docs/operate/audit',
            'docs/operate/audit-export',
            'docs/operate/retention',
            'docs/operate/metrics',
            'docs/operate/private-registries',
            'docs/operate/upgrading',
            'docs/operate/backup-restore',
            'docs/operate/default-prices',
            'docs/operate/sandbox-break-glass',
            'docs/operate/secret-keys',
          ],
        },
        {
          label: 'Use Koinon',
          items: [
            'docs/use/tasks-and-inbox',
            'docs/use/ask-user',
            'docs/use/triggers',
            'docs/use/scoped-approvals',
            'docs/use/home-checkpoints',
          ],
        },
        { label: 'Contribute', items: ['docs/contribute'] },
      ],
    }),
  ],
})
