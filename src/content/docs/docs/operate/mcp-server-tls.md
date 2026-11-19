---
title: MCP server certificates
description: Trust a private certificate authority for one MCP server, or turn off the certificate check for a test host.
area: connectors-tools
tags: [mcp, tls, egress]
audience: [operator]
---

:::note
This page is for the next Koinon release. It is not in v0.1.0-rc.25.
:::

Some MCP servers use a certificate from a private certificate authority (CA). Some test hosts use a
self-signed certificate. Koinon has two optional fields on each MCP server for these cases. The fields
work like the options of common tools.

| Field | Meaning | Like |
| --- | --- | --- |
| `caBundle` | Koinon trusts only this CA for this server. The public roots are not added. | `curl --cacert` |
| `insecureSkipVerify` | Koinon uses TLS but does not check the server certificate. The UI shows the server as "Not verified". | `curl -k` |

A server with neither field uses the public roots.

## Rules

- `caBundle` and `insecureSkipVerify` together are refused.
- Both fields need an `https` URL. Either field on an `http` URL is refused.
- A server with a credential needs an `https` URL. Plain `http` is allowed only for a loopback address.
- A `caBundle` is PEM text with certificates only, never a key. It never widens trust for another server.
- Size limits for all `caBundle` values:
  - 64 KiB for each server.
  - 128 KiB for each org.
  - 256 KiB for the whole installation.
- Koinon refuses a save that passes a limit.

Koinon checks a new server with one request. The request uses only your `caBundle`. If you set
`insecureSkipVerify`, the request does not check the certificate. If the certificate does not verify, the
error says to put the CA in `caBundle`.

## Warning: insecureSkipVerify

:::caution
Use `insecureSkipVerify` only for test hosts. With the check off, Koinon cannot tell the server from an
impostor. Koinon can send the server credential to an impostor. The audit log records the setting.
:::

Use `caBundle` for a server with a private CA. It keeps the identity check.

## Set the fields in the UI

1. Open **MCP servers** in the sidebar. Choose **Add server**, or edit a server.
2. To trust a private CA, paste the PEM text in **CA certificate (optional)**.
3. To turn off the check, select **Skip certificate verification (insecure)**. The form shows a warning.
4. The server list and the detail page show **Not verified** for a server with the check off.

## Set the fields with the API

The admin API (`/admin/v1/mcp-servers`, `POST` and `PATCH`) takes the same two fields:

```json
{
  "name": "tracker",
  "url": "https://mcp.tracker.internal.example/mcp",
  "transport": "streamable-http",
  "caBundle": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n"
}
```

For a test host, send `"insecureSkipVerify": true` and no `caBundle`. See `/admin/v1/openapi.yaml`.

## Set the fields in a declared Secret

A Secret that declares a server ([MCP servers](/docs/operate/mcp-servers/)) uses these keys:

```yaml
stringData:
  name: tracker
  url: https://mcp.tracker.internal.example/mcp
  transport: streamable-http
  caBundle: |
    -----BEGIN CERTIFICATE-----
    ...
    -----END CERTIFICATE-----
  # or, for a test host only:
  # insecureSkipVerify: "true"
```

`insecureSkipVerify` is `true` or `false`. Any other value makes Koinon ignore the Secret with a Warning
Event. The same rules and limits apply as for the UI and the API.

## Gateway mode

The `standalone` gateway mode supports both fields. The target gets its own CA or its own skip setting.
Other servers keep the public roots.

The `kubernetes` gateway mode cannot render a CA for one target. In this mode Koinon refuses both fields
when you save a server. The message names `gateway.mode=standalone`. Use `gateway.mode=standalone`, or use
a server with a certificate from a public CA. See [Gateway modes](/docs/operate/gateway-modes/).

See also [ADR 0057](https://github.com/stateracloud/koinon/blob/main/docs/adr/0057-mcp-servers.md).
