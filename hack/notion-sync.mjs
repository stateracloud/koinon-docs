#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0
//
// Copies Koinon's documentation into Notion. Git stays the source of truth: every run overwrites
// the Notion pages it manages, and a page whose source file is gone is archived.
//
// Three Notion databases, one per category:
//   Platform Docs  src/content/docs/docs/**/*.md of this repository
//   ADRs           docs/adr/NNNN-*.md of stateracloud/koinon
//   Research       docs/research/*.md and docs/spikes/*.md of stateracloud/koinon
//
// Each page carries the property Path (the source path, the key the sync matches on) and Hash (the
// sha256 of the source). A page whose Hash matches is left alone, so a run with no changes makes no
// writes beyond the query. The databases are made once by hand or by an agent; the schema and the setup are in
// README.md ("Notion copy").
//
// Usage:
//   hack/notion-sync.mjs                 sync (needs NOTION_TOKEN and the NOTION_DS_* variables)
//   hack/notion-sync.mjs --dry-run       read Notion, print what would change, write nothing
//   hack/notion-sync.mjs --force         rewrite every page, also those whose Hash matches (after a
//                                        change to the converter below)
//   hack/notion-sync.mjs --emit <dir>    write the prepared pages as JSON to <dir> and convert each
//                                        to blocks; touches no Notion (CI runs this on every change)
//
// Environment:
//   NOTION_TOKEN          internal integration token (a secret; never commit it)
//   NOTION_DS_PLATFORM    data source ID of Platform Docs
//   NOTION_DS_ADRS        data source ID of ADRs
//   NOTION_DS_RESEARCH    data source ID of Research
//   KOINON_MAIN_SRC       a checkout of stateracloud/koinon at main (default: fetched shallow)
//   KOINON_REPO           where to fetch it from (default https://github.com/stateracloud/koinon.git)

import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join, posix, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Lexer } from 'marked';

const DOCS_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SITE = 'https://koinon.stateracloud.com';
const DOCS_REPO = 'https://github.com/stateracloud/koinon-docs';
const KOINON_REPO_WEB = 'https://github.com/stateracloud/koinon';
const NOTION_API = 'https://api.notion.com/v1';
const NOTION_VERSION = '2025-09-03'; // data sources: a database can hold several
const TEXT_LIMIT = 2000; // characters per rich text object
const CHILD_LIMIT = 100; // blocks per append request

// ---------------------------------------------------------------------------------------------
// Sources

function koinonSource() {
  if (process.env.KOINON_MAIN_SRC) return process.env.KOINON_MAIN_SRC;
  const dir = join(mkdtempSync(join(tmpdir(), 'notion-sync-')), 'koinon');
  const repo = process.env.KOINON_REPO || `${KOINON_REPO_WEB}.git`;
  execFileSync('git', ['clone', '-q', '--depth', '1', '--filter=blob:none', '--sparse', repo, dir], { stdio: 'inherit' });
  execFileSync('git', ['-C', dir, 'sparse-checkout', 'set', 'docs'], { stdio: 'inherit' });
  return dir;
}

function listMarkdown(dir) {
  let out = [];
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) out = out.concat(listMarkdown(p));
    else if (e.name.endsWith('.md')) out.push(p);
  }
  return out.sort();
}

function frontmatter(text) {
  const m = text.match(/^---\n([\s\S]*?)\n---\n/);
  if (!m) return { meta: {}, body: text };
  const meta = {};
  for (const line of m[1].split('\n')) {
    const kv = line.match(/^([A-Za-z_]+):\s*(.*)$/);
    if (!kv) continue;
    const v = kv[2].trim();
    meta[kv[1]] = v.startsWith('[') ? v.replace(/^\[|\]$/g, '').split(',').map((x) => x.trim().replace(/^(['"])(.*)\1$/, '$2')).filter(Boolean) : v.replace(/^(['"])(.*)\1$/, '$2');
  }
  return { meta, body: text.slice(m[0].length) };
}

// Takes the first `# Title` off the body; Notion shows the title as the page title.
function takeTitle(body) {
  const m = body.match(/^\s*# (.+)\n/);
  if (!m) return { title: null, body };
  return { title: m[1].trim(), body: body.slice(m[0].length) };
}

function stripComments(body) {
  return body.replace(/<!--[\s\S]*?-->\n?/g, '').replace(/\{\/\*[\s\S]*?\*\/\}\n?/g, '');
}

// Rewrites links so they work outside the repository: relative links in the Koinon repository go
// to GitHub at main, absolute /docs/ links go to the docs site. Code is left untouched.
function rewriteLinks(body, resolve) {
  const parts = body.split(/(^(?:```|~~~)[\s\S]*?^(?:```|~~~)[^\n]*$|`[^`\n]*`)/m);
  return parts
    .map((part, i) => (i % 2 === 1 ? part : part.replace(/\]\(([^)\s]+)(\s+"[^"]*")?\)/g, (all, url, t) => `](${resolve(url)}${t || ''})`)))
    .join('');
}

// Relative links resolve against the file's directory, a leading `/` against the repository root
// (as GitHub renders them), and `#section` against the page itself.
function koinonResolver(repoPath) {
  const self = `${KOINON_REPO_WEB}/blob/main/${repoPath}`;
  return (url) => {
    if (/^[a-z]+:/i.test(url)) return url;
    if (url.startsWith('#')) return self + url;
    const [p, hash] = url.split('#');
    const target = p.startsWith('/') ? posix.normalize(p.slice(1)) : posix.normalize(posix.join(posix.dirname(repoPath), p));
    return `${KOINON_REPO_WEB}/blob/main/${target}${hash ? `#${hash}` : ''}`;
  };
}

// Absolute links go to the docs site, `#section` to the page itself on the site.
function siteResolver(pageUrl) {
  return (url) => {
    if (url.startsWith('#')) return pageUrl + url;
    if (url.startsWith('/')) return SITE + url;
    return url;
  };
}

function sha256(text) {
  return createHash('sha256').update(text).digest('hex');
}

function sourceNote(url) {
  return `> Synced from [${url.replace('https://github.com/', '')}](${url}). Edit the source in Git; this page is overwritten.\n\n`;
}

// header <body> <key>: the value of `- Key:` above the first `## ` heading (ADR 0115).
function headerField(body, key) {
  const head = body.split(/^## /m)[0];
  const m = head.match(new RegExp(`^- ${key}:\\s*(.+)$`, 'm'));
  return m ? m[1].trim() : '';
}
const tagList = (s) => s.split(',').map((t) => t.trim()).filter(Boolean);
const unlink = (s) => s.replace(/\[([^\]]*)\]\([^)]*\)/g, '$1');

const ADR_STATES = ['Proposed', 'Accepted', 'Superseded', 'Deprecated', 'Rejected'];

function collectAdrs(src) {
  const dir = join(src, 'docs/adr');
  return readdirSync(dir)
    .filter((f) => /^\d{4}-.+\.md$/.test(f) && !f.startsWith('0000-'))
    .sort()
    .map((f) => {
      const repoPath = `docs/adr/${f}`;
      const raw = readFileSync(join(dir, f), 'utf8');
      const { title, body } = takeTitle(stripComments(raw));
      const status = ((body.match(/^- Status:\s*(.+)$/m) || [])[1] || '').replace(/\[([^\]]*)\]\([^)]*\)/g, '$1');
      const date = (body.match(/^- Date:\s*(\d{4}-\d{2}-\d{2})/m) || [])[1] || null;
      const state = ADR_STATES.find((s) => status.toLowerCase().startsWith(s.toLowerCase())) || 'Other';
      const source = `${KOINON_REPO_WEB}/blob/main/${repoPath}`;
      return {
        db: 'adrs',
        path: repoPath,
        hash: sha256(raw),
        title: (title || f).replace(/^\d{4}\.\s*/, ''),
        props: { Number: Number(f.slice(0, 4)), State: state, Status: status, Date: date, Area: headerField(body, 'Area'), Tags: tagList(headerField(body, 'Tags')) },
        source,
        markdown: sourceNote(source) + rewriteLinks(body, koinonResolver(repoPath)),
      };
    });
}

function collectResearch(src) {
  return ['research', 'spikes'].flatMap((sub) =>
    listMarkdown(join(src, 'docs', sub))
      .filter((p) => basename(p) !== 'README.md')
      .map((p) => {
        const repoPath = relative(src, p).split('\\').join('/');
        const raw = readFileSync(p, 'utf8');
        const { title, body } = takeTitle(stripComments(raw));
        const source = `${KOINON_REPO_WEB}/blob/main/${repoPath}`;
        const status = unlink(headerField(body, 'Status'));
        const stage = ['Draft', 'Complete', 'Abandoned', 'Superseded'].find((x) => status.startsWith(x)) || '';
        return {
          db: 'research',
          path: repoPath,
          hash: sha256(raw),
          title: title || basename(p, '.md'),
          props: {
            Kind: sub === 'spikes' ? 'Spike' : 'Research',
            Stage: stage,
            Status: status,
            Date: (headerField(body, 'Date').match(/^\d{4}-\d{2}-\d{2}/) || [])[0] || null,
            Area: headerField(body, 'Area'),
            Tags: tagList(headerField(body, 'Tags')),
          },
          source,
          markdown: sourceNote(source) + rewriteLinks(body, koinonResolver(repoPath)),
        };
      }),
  );
}

const SECTIONS = { start: 'Start', use: 'Use', operate: 'Operate' };

function collectPlatform() {
  const base = join(DOCS_ROOT, 'src/content/docs/docs');
  return listMarkdown(base).map((p) => {
    const rel = relative(base, p).split('\\').join('/');
    const repoPath = `src/content/docs/docs/${rel}`;
    const raw = readFileSync(p, 'utf8');
    const { meta, body } = frontmatter(stripComments(raw));
    const slug = rel.replace(/(^|\/)index\.md$/, '$1').replace(/\.md$/, '/');
    const source = `${SITE}/docs/${slug}`;
    const top = rel.includes('/') ? rel.split('/')[0] : '';
    return {
      db: 'platform',
      path: repoPath,
      hash: sha256(raw),
      title: meta.title || basename(p, '.md'),
      props: {
        Section: SECTIONS[top] || 'Overview',
        Description: meta.description || '',
        Area: meta.area || '',
        Tags: Array.isArray(meta.tags) ? meta.tags : [],
        Audience: Array.isArray(meta.audience) ? meta.audience : [],
      },
      source,
      markdown:
        `> Synced from [${source.replace('https://', '')}](${source}) ([source](${DOCS_REPO}/blob/main/${repoPath})). Edit the source in Git; this page is overwritten.\n\n` +
        rewriteLinks(body, siteResolver(source)),
    };
  });
}

// Checks the metadata of ADR 0115 against the Koinon repository's vocabulary. The Koinon repository
// checks its own documents (hack/doc-meta-lint.sh); the same rules are repeated here so the pages of
// this repository are held to them, and so a bad value never reaches Notion.
function vocabulary(src, name) {
  return new Set(
    readFileSync(join(src, 'docs/metadata', name), 'utf8')
      .split('\n')
      .map((l) => l.trim())
      .filter((l) => l && !l.startsWith('#'))
      .map((l) => l.split(/\s+/)[0]),
  );
}

function validate(docs, src) {
  const areas = vocabulary(src, 'areas.txt');
  const tags = vocabulary(src, 'tags.txt');
  const errors = [];
  for (const d of docs) {
    const { Area, Tags = [] } = d.props;
    if (!areas.has(Area)) errors.push(`${d.path}: area '${Area || ''}' is not in docs/metadata/areas.txt`);
    if (Tags.length < 1 || Tags.length > 6) errors.push(`${d.path}: needs one to six tags (has ${Tags.length})`);
    if (new Set(Tags).size !== Tags.length) errors.push(`${d.path}: a tag is listed twice`);
    for (const t of Tags) if (!tags.has(t)) errors.push(`${d.path}: tag '${t}' is not in docs/metadata/tags.txt`);
    if (d.db === 'platform') {
      if (!d.props.Description) errors.push(`${d.path}: needs a description`);
      if (!d.props.Audience.length) errors.push(`${d.path}: needs an audience (user, operator, contributor)`);
    }
  }
  return errors;
}

// ---------------------------------------------------------------------------------------------
// Markdown to Notion blocks

const LANGS = new Set(['bash', 'c', 'c++', 'css', 'diff', 'docker', 'go', 'graphql', 'html', 'java', 'javascript', 'json', 'makefile', 'markdown', 'plain text', 'protobuf', 'python', 'rust', 'shell', 'sql', 'typescript', 'xml', 'yaml']);
const LANG_ALIAS = { sh: 'shell', console: 'shell', zsh: 'shell', js: 'javascript', ts: 'typescript', yml: 'yaml', md: 'markdown', proto: 'protobuf', dockerfile: 'docker', text: 'plain text', txt: 'plain text', '': 'plain text', py: 'python', golang: 'go', jsonc: 'json', tsx: 'typescript', mjs: 'javascript', cel: 'plain text' };

function lang(info) {
  const l = (info || '').split(/\s+/)[0].toLowerCase();
  const n = LANG_ALIAS[l] ?? l;
  return LANGS.has(n) ? n : 'plain text';
}

function chunkText(content, annotations, link) {
  const out = [];
  for (let i = 0; i < content.length; i += TEXT_LIMIT) {
    const text = { content: content.slice(i, i + TEXT_LIMIT) };
    if (link && /^https?:\/\//.test(link)) text.link = { url: link };
    out.push({ type: 'text', text, annotations: { ...annotations } });
  }
  return out;
}

function decode(s) {
  return s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, '&');
}

function inline(tokens, ann = {}, link = null) {
  const out = [];
  for (const t of tokens || []) {
    switch (t.type) {
      case 'strong':
        out.push(...inline(t.tokens, { ...ann, bold: true }, link));
        break;
      case 'em':
        out.push(...inline(t.tokens, { ...ann, italic: true }, link));
        break;
      case 'del':
        out.push(...inline(t.tokens, { ...ann, strikethrough: true }, link));
        break;
      case 'codespan':
        out.push(...chunkText(decode(t.text), { ...ann, code: true }, link));
        break;
      case 'link':
        out.push(...inline(t.tokens, ann, t.href));
        break;
      case 'image':
        out.push(...chunkText(t.text || t.href, ann, t.href));
        break;
      case 'br':
        out.push(...chunkText('\n', ann, link));
        break;
      case 'text':
        if (t.tokens) out.push(...inline(t.tokens, ann, link));
        else out.push(...chunkText(decode(t.text), ann, link));
        break;
      case 'escape':
      case 'html':
      default:
        out.push(...chunkText(decode(t.text ?? t.raw ?? ''), ann, link));
    }
  }
  return mergeRuns(out);
}

// Joins neighbouring runs with the same style and caps the array at Notion's 100 items.
function mergeRuns(runs) {
  const out = [];
  for (const r of runs) {
    const prev = out[out.length - 1];
    if (prev && JSON.stringify(prev.annotations) === JSON.stringify(r.annotations) && JSON.stringify(prev.text.link) === JSON.stringify(r.text.link) && prev.text.content.length + r.text.content.length <= TEXT_LIMIT) {
      prev.text.content += r.text.content;
    } else out.push(r);
  }
  if (out.length > 100) {
    const rest = out.slice(99).map((r) => r.text.content).join('');
    return out.slice(0, 99).concat(chunkText(rest.slice(0, TEXT_LIMIT), {}));
  }
  return out;
}

function textBlock(type, rich, extra = {}) {
  return { object: 'block', type, [type]: { rich_text: rich, ...extra } };
}

function blocks(tokens) {
  const out = [];
  for (const t of tokens) {
    switch (t.type) {
      case 'heading': {
        const level = Math.min(t.depth, 3);
        out.push(textBlock(`heading_${level}`, inline(t.tokens)));
        break;
      }
      case 'paragraph':
        out.push(...splitParagraph(inline(t.tokens)));
        break;
      case 'code': {
        const runs = chunkText(t.text, {});
        for (let i = 0; i < runs.length; i += 100) out.push(textBlock('code', runs.slice(i, i + 100), { language: lang(t.lang) }));
        break;
      }
      case 'blockquote': {
        const inner = blocks(t.tokens);
        const head = inner[0]?.type === 'paragraph' ? inner.shift().paragraph.rich_text : [];
        out.push({ object: 'block', type: 'quote', quote: { rich_text: head, children: inner.length ? inner : undefined } });
        break;
      }
      case 'list':
        for (const item of t.items) {
          const type = item.task ? 'to_do' : t.ordered ? 'numbered_list_item' : 'bulleted_list_item';
          const [lead, ...rest] = item.tokens;
          let rich = [];
          let children = [];
          if (lead && (lead.type === 'text' || lead.type === 'paragraph')) {
            rich = inline(lead.tokens || [{ type: 'text', text: lead.text }]);
            children = blocks(rest);
          } else children = blocks(item.tokens);
          const extra = item.task ? { checked: !!item.checked } : {};
          const b = textBlock(type, rich, extra);
          if (children.length) b[type].children = children;
          out.push(b);
        }
        break;
      case 'table': {
        const width = t.header.length;
        const row = (cells) => ({ object: 'block', type: 'table_row', table_row: { cells: cells.map((c) => inline(c.tokens)) } });
        out.push({ object: 'block', type: 'table', table: { table_width: width, has_column_header: true, has_row_header: false, children: [row(t.header), ...t.rows.map(row)] } });
        break;
      }
      case 'hr':
        out.push({ object: 'block', type: 'divider', divider: {} });
        break;
      case 'html':
        if (t.text.trim()) out.push(textBlock('paragraph', chunkText(t.text.trim(), {})));
        break;
      case 'space':
        break;
      default:
        if (t.raw && t.raw.trim()) out.push(textBlock('paragraph', chunkText(t.raw.trim(), {})));
    }
  }
  return out;
}

// A paragraph with more than 100 rich text runs becomes several paragraphs.
function splitParagraph(rich) {
  const out = [];
  for (let i = 0; i < rich.length; i += 100) out.push(textBlock('paragraph', rich.slice(i, i + 100)));
  return out.length ? out : [];
}

export function toBlocks(markdown) {
  return blocks(new Lexer({ gfm: true }).lex(markdown));
}

// ---------------------------------------------------------------------------------------------
// Notion API

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function notion(method, path, body) {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(NOTION_API + path, {
      method,
      headers: {
        Authorization: `Bearer ${process.env.NOTION_TOKEN}`,
        'Notion-Version': NOTION_VERSION,
        'Content-Type': 'application/json',
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (res.ok) {
      await sleep(340); // stay under the average of three requests a second
      return res.json();
    }
    if ((res.status === 429 || res.status >= 500) && attempt < 6) {
      const wait = Number(res.headers.get('retry-after')) * 1000 || 1000 * 2 ** attempt;
      await sleep(wait);
      continue;
    }
    throw new Error(`${method} ${path}: ${res.status} ${await res.text()}`);
  }
}

async function existingPages(dsId) {
  const map = new Map();
  let cursor;
  do {
    const r = await notion('POST', `/data_sources/${dsId}/query`, { page_size: 100, start_cursor: cursor });
    for (const p of r.results) {
      const path = p.properties.Path?.rich_text?.map((t) => t.plain_text).join('') || '';
      const hash = p.properties.Hash?.rich_text?.map((t) => t.plain_text).join('') || '';
      if (path) map.set(path, { id: p.id, hash });
    }
    cursor = r.has_more ? r.next_cursor : undefined;
  } while (cursor);
  return map;
}

const rt = (s) => (s ? chunkText(s, {}).slice(0, 100) : []);

function properties(doc, now) {
  const p = {
    Title: { title: rt(doc.title) },
    Path: { rich_text: rt(doc.path) },
    Hash: { rich_text: rt(doc.hash) },
    Source: { url: doc.source },
    Synced: { date: { start: now } },
  };
  for (const [k, v] of Object.entries(doc.props)) {
    if (k === 'Number') p[k] = { number: v };
    else if (k === 'Date') p[k] = { date: v ? { start: v } : null };
    else if (['State', 'Section', 'Kind', 'Area', 'Stage'].includes(k)) p[k] = { select: v ? { name: v } : null };
    else if (Array.isArray(v)) p[k] = { multi_select: v.map((name) => ({ name })) };
    else p[k] = { rich_text: rt(v) };
  }
  return p;
}

// Appends blocks level by level: a request carries one level, then each block's children follow
// under the ID Notion returns. That keeps every request inside the nesting and size limits.
async function append(parentId, list) {
  for (let i = 0; i < list.length; i += CHILD_LIMIT) {
    const batch = list.slice(i, i + CHILD_LIMIT);
    const kids = batch.map((b) => {
      const inner = b[b.type];
      if (b.type === 'table') return null; // table rows must travel with their table
      const c = inner.children;
      delete inner.children;
      return c && c.length ? c : null;
    });
    const r = await notion('PATCH', `/blocks/${parentId}/children`, { children: batch });
    for (let j = 0; j < kids.length; j++) if (kids[j]) await append(r.results[j].id, kids[j]);
  }
}

async function clear(pageId) {
  let cursor;
  const ids = [];
  do {
    const r = await notion('GET', `/blocks/${pageId}/children?page_size=100${cursor ? `&start_cursor=${cursor}` : ''}`);
    ids.push(...r.results.map((b) => b.id));
    cursor = r.has_more ? r.next_cursor : undefined;
  } while (cursor);
  for (const id of ids) await notion('DELETE', `/blocks/${id}`);
}

// ---------------------------------------------------------------------------------------------

async function main() {
  const args = process.argv.slice(2);
  const emit = args.includes('--emit') ? args[args.indexOf('--emit') + 1] : null;
  const dryRun = args.includes('--dry-run');
  const force = args.includes('--force');

  const src = koinonSource();
  const docs = [...collectPlatform(), ...collectAdrs(src), ...collectResearch(src)];
  const errors = validate(docs, src);
  if (errors.length) {
    for (const e of errors) console.error(`metadata: ${e}`);
    console.error(`${errors.length} metadata errors; see docs/dev/doc-metadata.md in the Koinon repository`);
    process.exit(1);
  }

  if (emit) {
    mkdirSync(emit, { recursive: true });
    let n = 0;
    for (const d of docs) {
      writeFileSync(join(emit, `${d.db}--${d.path.replace(/[/.]/g, '_')}.json`), JSON.stringify(d, null, 2));
      n += toBlocks(d.markdown).length;
    }
    console.log(`wrote ${docs.length} pages (${n} top-level blocks) to ${emit}`);
    return;
  }

  const dbs = { platform: process.env.NOTION_DS_PLATFORM, adrs: process.env.NOTION_DS_ADRS, research: process.env.NOTION_DS_RESEARCH };
  const missing = ['NOTION_TOKEN', 'NOTION_DS_PLATFORM', 'NOTION_DS_ADRS', 'NOTION_DS_RESEARCH'].filter((k) => !process.env[k]);
  if (missing.length) {
    console.error(`missing: ${missing.join(' ')}`);
    process.exit(2);
  }

  const now = new Date().toISOString();
  const counts = { created: 0, updated: 0, unchanged: 0, archived: 0 };
  for (const [db, dbId] of Object.entries(dbs)) {
    const have = await existingPages(dbId);
    const want = docs.filter((d) => d.db === db);
    for (const d of want) {
      const cur = have.get(d.path);
      have.delete(d.path);
      if (cur && cur.hash === d.hash && !force) {
        counts.unchanged++;
        continue;
      }
      console.log(`${cur ? 'update' : 'create'} ${d.path}`);
      if (dryRun) continue;
      const body = toBlocks(d.markdown);
      if (cur) {
        await clear(cur.id);
        await append(cur.id, body);
        // The hash goes last, so a run that dies half way redoes this page next time.
        await notion('PATCH', `/pages/${cur.id}`, { properties: properties(d, now) });
        counts.updated++;
      } else {
        const props = properties(d, now);
        props.Hash = { rich_text: [] };
        const page = await notion('POST', '/pages', { parent: { type: 'data_source_id', data_source_id: dbId }, properties: props });
        await append(page.id, body);
        await notion('PATCH', `/pages/${page.id}`, { properties: { Hash: { rich_text: rt(d.hash) } } });
        counts.created++;
      }
    }
    for (const [path, { id }] of have) {
      console.log(`archive ${path}`);
      if (!dryRun) await notion('PATCH', `/pages/${id}`, { archived: true });
      counts.archived++;
    }
  }
  console.log(`${dryRun ? 'dry run: ' : ''}${JSON.stringify(counts)}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((e) => {
    console.error(e.message);
    process.exit(1);
  });
}
