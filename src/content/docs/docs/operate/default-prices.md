---
title: "Default prices: sources, updates and overrides"
description: Where Koinon's default model prices come from, how they update and how admins override them.
area: models-spend
tags: [pricing, spend-ledger]
audience: [operator]
---

Koinon prices every model request itself, from the raw usage and a dated price. This runbook says
where the default prices come from, how they update and how admins override them. The design is
in [ADR 0056](https://github.com/stateracloud/koinon/blob/main/docs/adr/0056-model-providers-pricing-and-budgets-per-org.md).

## The default list

The built-in price list ships inside the release, in the `koinon-api` binary. An operator cannot edit it.
The steps that change it are in the Koinon repository
([prices guide](https://github.com/stateracloud/koinon/blob/v0.1.0-rc.13/docs/ops/prices.md)).
Each ledger entry cites the price version it used (`default@<version>#<id>`).

Some entries list hosts they do not apply to. The built-in `ollama-local` entry does not apply to `ollama.com`,
where Ollama cloud bills per token. A model on an `ollama` provider that points to the cloud is unpriced
(refused) until an admin sets an org price.

**After an upgrade.** `koinon-api` records each list version it runs. Ask what changed with
`GET /admin/v1/prices/defaults/changes` (without parameters: the current version against the one
before), or `PriceService.GetDefaultPriceChanges` in the UI.

## Org prices (overrides)

An org admin adds prices of their own with `POST /admin/v1/prices` (or `PriceService.SetPrice`).
They win over the default list. A price has a name; setting the same name again adds a version that
applies from its `validFrom` (default now), and earlier versions never change, so past requests keep
the price they were charged at. `DELETE /admin/v1/prices/{name}` ends the price. Every change is audited. The UI is the *Prices*
page (Settings, owners and admins). An org price with a non-zero rate needs `max_output`, and the API
refuses one without it. On an upgrade from a release that had per-model `rates`, those were folded into org
prices, and `rates` are refused now.

## The platform price list (updates between releases)

Between an org's own prices and the default list sits the **platform list**: an install-wide price
list in Postgres, versioned and append-only. A request is priced by the first of three layers that
names its model: the org price, then the platform list, then the default list. Ledger rows cite a
platform price as `platform@<version>#<entry id>`. The design is
[ADR 0098](https://github.com/stateracloud/koinon/blob/main/docs/adr/0098-price-catalogue-updates-from-public-sources.md); this release fetches from OpenRouter
only, and only from the command line.

**Three modes.** `prices.refresh.enabled` in the chart picks one; the chart passes it to `koinon-api`
as `--prices-refresh=auto|off|on` and knows nothing about providers:

| `prices.refresh.enabled` | Mode | What `koinon-api` fetches |
|---|---|---|
| unset (the default) | `auto` | OpenRouter's public price list, only while some org has a provider of type `openrouter` (checked again on every tick, so adding or removing the provider takes effect within the hour) |
| `false` | `off` | nothing: no request to any price source; prices change only with an upgrade or when you fetch and accept a proposal yourself |
| `true` | `on` | every source Koinon has an adapter for, whatever providers exist |

In `auto` and `on` the fetched proposals within the bounds apply by themselves (below). **The first
day brings no OpenRouter estimate**: a fetched price counts only after two fetches 24 hours apart
agree, so a new install with an OpenRouter provider has no price for its OpenRouter models until the
second day, unless you set an org price or accept a proposal. A model Koinon has no price for at all
applies by itself the same way, once two fetches 24 hours apart returned the same values: it has
no earlier price, so the 25% bound does not apply to it, but every other rule does (no zero rate,
no suspected unit mix-up between its own rates, nothing above 1000 USD per million, an output
limit from the source, and the daily cap, which it counts towards). Its first applied price is
the one later automatic changes are measured against until you accept one yourself.

**Unpriced models.** At start and on every tick `koinon-api` counts the enabled models of enabled
providers of a type Koinon fetches prices for (today `openrouter`) that no layer prices and logs a warning with the count per provider type (no model or org
names); the gauge is `koinon_price_unpriced_models{provider_type}`.

Run the commands in a `koinon-api` pod:

```sh
kubectl -n koinon exec deploy/koinon-api -- koinon-api prices fetch
kubectl -n koinon exec deploy/koinon-api -- koinon-api prices proposals list
kubectl -n koinon exec deploy/koinon-api -- koinon-api prices proposals accept <id>
kubectl -n koinon exec deploy/koinon-api -- koinon-api prices proposals dismiss <id>
kubectl -n koinon exec deploy/koinon-api -- koinon-api prices platform rollback <version>
```

`prices fetch` makes one unauthenticated request to `https://openrouter.ai/api/v1/models` (nothing
about your install is sent) and compares it with the price each of your models has now. It stores
**proposals** and applies nothing. For an install that cannot reach OpenRouter, run
`koinon-api prices fetch --out prices.json` anywhere (it needs no database), carry the file over and
load it with `koinon-api prices import prices.json`. You vouch for an imported file: its proposals
are never applied by themselves, and they are kept apart from the fetch proposals for the same
values. The file's fetch time is recorded, but it never delays the scheduled fetch or moves the
model-count floor of a live fetch. A file with no `fetchedAt`, one more than 5 minutes in the
future, or a model count below its offers is refused.

**Classes.** Every proposal has a class, from fixed rules in the code:

| Class | Meaning | What you do |
|---|---|---|
| `auto` | at most 25% off the last price a person reviewed (or a model with no price yet), no new or removed rate, none zero, the same values in two fetches 24 hours apart | nothing, in `auto` or `on`; with `off`, accept it |
| `needs_review` | anything else that is plausible (a first sighting, a bigger move, a new rate, a tier change, a new model with a zero rate or no output limit, an import) | `accept` or `dismiss` |
| `confirm` | more than 3 times up or down, a rate that fell to zero, a suspected unit mix-up (a ratio of 100 or more to the current rate, or for a new model between its own rates), or a rate above 1000 USD per million | `accept --confirm <model id>`, typed in full |
| `refused` | the source's data cannot be made into a price (a negative or variable price, an unreadable rate) | nothing; it cannot be accepted |

A source that reports no output limit for a model (OpenRouter's `max_completion_tokens` is null) makes
a `needs_review` proposal: accept it with `accept <id> --max-output <tokens>`, which sets the entry's
`max_output` (the `why:` line says so).

Why a proposal is not `auto` is in `proposals list` (`why:`). A dismissed proposal does not come back
for the same values from the same source. Accepting writes a new platform version valid from now on,
never in the past, so charged requests keep their price. `prices platform rollback <version>` writes
a new version equal to an older one. Platform prices are always for one model name: an entry that
covers other models too (a pattern) is not changed, the proposal makes an entry of its own.

**Small price changes apply by themselves** in `auto` and `on`: `koinon-api` fetches each active
source on the interval (`prices.refresh.interval`, default `24h`, at least `1h`) and applies the
`auto` proposals, at most 10 in 24 hours (more than that means a broken source, and all wait for a
person). Each candidate is classified again under the current bounds just before it is applied, and
a source whose fetch failed applies nothing on that tick. You can tighten the bounds
(`prices.refresh.maxChangePercent`, 1-25, and `prices.refresh.maxAutoPerDay`, 1-10), never loosen
them; `koinon-api` stores them, and `prices fetch` on the command line classifies with the stored
bounds too. Every change is audited; roll back with the command above.

**When the default list catches up.** On start `koinon-api` retires a platform entry that equals the
new default entry of the same id (`platform_price.retired`, the reason names the list version). If
that fails, `koinon-api` logs a warning and starts anyway.

**A stored platform entry this version refuses** (one written under an older release's rules that
no longer validates) is skipped: its models are priced from the default list, the rest of the
version still applies, `koinon_price_platform_bad_entries` counts them and a warning says how many.
Auto-apply and retirement then wait (they would drop the entry without a person deciding); roll
back to a good version or accept a proposal, which writes a version without the bad entries and
says in its audit event how many it dropped (`droppedBadEntries`).

**Audit.** Every price change is an event in the install audit chain (ADR 0100), which belongs to no
org and needs no platform admin: `price.proposal.accepted`, `price.proposal.dismissed`,
`platform_price.set`, `platform_price.rollback`, `platform_price.retired`, `price.import.uploaded`
and `price.refresh.settings_changed`. The actor is the person (`user <id>`), the command line
(`cli`) or, for the scheduled fetch's auto-apply and `koinon-api`'s start-up bookkeeping (the stored
refresh settings, a retirement when the default list catches up), `system koinon-api:price-refresh`.
A fresh install with no platform admin is audited like any other, and the bounded auto-apply does
not wait for an admin. A platform admin reads the chain with `AuditService.List` (scope install), the
admin API (`GET /admin/v1/audit?scope=install`, for a token whose root user is a platform admin)
and verifies it with `koinon-api audit verify` (`--install` for the install chain alone). Events written before
this change are in the personal orgs of the platform admins of that time; no backfill is made.

**Metrics.** `koinon_price_source_fetch_total{source,result}`, `koinon_price_proposals{class,state}`,
`koinon_price_auto_applied_total{source}`, `koinon_price_unpriced_models{provider_type}` and
`koinon_price_platform_bad_entries` (no labels).

**Tiers.** OpenRouter's `min_prompt_tokens` override applies to a prompt strictly greater than
that many tokens, as OpenRouter's SDK documents (ADR 0098), so it becomes `context_over` unchanged.
Several overrides combine as OpenRouter applies them: later ones win per rate, a rate an override
does not set keeps the base price, and an override with a time condition is never a tier.

**Known limits.** Time-of-day, batch, flex
and priority prices, per-upstream prices and 1-hour cache writes are not imported. Not built yet: the models.dev, LiteLLM and genai-prices adapters, the
admin API and the Platform Prices page, org-admin acceptance into org entries (with their retirement
and the "source differs" mark), the in-app notice after an auto-apply, and the bill-gap view.

## Cost checks

Koinon's cost counts for limits and reports. agentgateway's cost from its access log is kept beside it;
when they differ by more than 1% the price entry is flagged (`GET /admin/v1/prices/flagged`, or the Flagged requests list on the Prices page, which also shows
usage that was missing, estimated output cut at the price's largest output, and prices that could not be used). A flag
usually means the gateway's catalog is out of date (a price changed since the last reconcile) or the
provider bills a bucket the entry does not price (an entry missing `cache_write`, for example).

## Estimates

When a provider reports no usage (an aborted stream), Koinon estimates it and marks the entry. The
method is in the ADR and in [the research](https://github.com/stateracloud/koinon/blob/main/docs/research/claude-token-estimation.md). OpenAI-family text is
counted with tiktoken. The tokenizer data is compiled into the binary; nothing is downloaded at run time.
An aborted response with no usage settles at the request's `max_tokens`, or at the price's `max_output`
when the request's limit was not logged.

## Upgrading from the first release (per-model rates)

The upgrade turns the rates set on each model into an org price entry (the design is in
[ADR 0056](https://github.com/stateracloud/koinon/blob/main/docs/adr/0056-model-providers-pricing-and-budgets-per-org.md)),
and `koinon-api` completes those entries at start from the matching default entry. Check three things:

- Entries with **Needs review** on the Prices page matched no default entry and have generic estimate
  settings. Save a new version with the right ones.
- `price.migration_skipped` events in the audit log name models whose rates could not be converted.
- GitOps users: `rates` in a model-provider Secret is now ignored (a Warning Event on every sync says so). A
  model added through a Secret with only `rates` is not served unless the default list covers it. Declare
  a price instead, on the Prices page or with `POST /admin/v1/prices`.
- During a rolling upgrade, rates written by an old pod are not converted.
