---
title: Sandbox size and defaults
description: How much CPU and memory an agent sandbox gets, the bounds that clamp it, the default-deny NetworkPolicy and the LimitRange of sandbox namespaces.
area: runtime-sandbox
tags: [sandbox, kubernetes, isolation]
audience: [operator]
---

Every agent sandbox gets CPU and memory requests and limits on the agent container, so the scheduler can place
sandboxes by what they need and one node cannot fill with pods that claim nothing
([ADR 0083](https://github.com/stateracloud/koinon/blob/main/docs/adr/0083-sandbox-resources.md)).

## How the size is chosen

For each of the four values (CPU request, CPU limit, memory request, memory limit), Koinon takes the first
that is set of: the agent's own override (an org admin sets it on the agent's page, "Sandbox size"), the
template's `spec.resources`, and the platform default. Then it clamps the value to the platform bounds. With
`memoryRequestEqualsLimit` the memory request becomes the limit, and a request above its limit is lowered to it.
The API refuses an override outside the bounds. The reconciler clamps again on every pass, because the bounds can
change after the write, and logs a clamp once.

The defaults and bounds are chart values:

```yaml chart-values
sandbox:
  resources:
    default:
      cpu: {request: 250m, limit: "2"}
      memory: {request: 1Gi, limit: 2Gi}
    bounds:
      cpu:
        request: {min: 100m, max: "2"}
        limit: {min: 100m, max: "4"}
      memory:
        request: {min: 512Mi, max: 8Gi}
        limit: {min: 512Mi, max: 8Gi}
    memoryRequestEqualsLimit: true
```

The values above are the defaults. The reconciler refuses to start on a bad quantity, a minimum above a maximum or
a default request above its limit. **Changing a value recreates the sandboxes it applies to once**, and each home
is restored from its checkpoint, so change them in a quiet hour. Recreates are rate-limited
(`reconciler.maxRecreatesPerPass`; see [Upgrading](/docs/operate/upgrading/)).

The default runtime class is Kata. A Kata guest never gives memory back to the host once it has used it, so a request
below the limit lets a node be over-committed on memory that cannot be reclaimed; that is why
`memoryRequestEqualsLimit` is on. Turn it off for a runtime that can reclaim memory. Settings by isolation tier:

| Tier | Memory | CPU | Request below limit |
| --- | --- | --- | --- |
| `vm` (Kata, the default) | 512Mi to 8Gi | request 100m to 2, limit up to 4 | no (`memoryRequestEqualsLimit: true`) |
| `hardened` (gVisor or runc with the hardened policy) | 256Mi to 8Gi | as above | allowed (`false`) |
| `dev` (kind, a laptop) | requests of 50m and 256Mi, a 1Gi limit, so a dozen sandboxes fit | | |

A Kata RuntimeClass must also carry `overhead.podFixed` memory and cpu for what a sandbox uses beyond its limits
(the guest kernel, the agent, the VM monitor); see [Upgrading](/docs/operate/upgrading/).

## Default-deny NetworkPolicy and LimitRange

In each OpenShell workspace namespace of `openshell.gatewayId` the reconciler applies two objects. Both switches are
on by default, and each also renders a ClusterRole, a binding and a ValidatingAdmissionPolicy that fence the
reconciler to this gateway's namespaces:

- `sandboxNetworkPolicy.enabled`: a NetworkPolicy named `<namespace>-<fullname>-sandbox-default-deny` with an empty pod
  selector, both policy types and no allow rules. OpenShell's own policies add to it. It needs a CNI that enforces
  NetworkPolicy and uses nothing CNI-specific.
- `sandboxLimitRange.enabled`: a LimitRange named `<namespace>-<fullname>-sandbox-limitrange` with a default request of 50m
  and 64Mi and a default limit of 250m and 256Mi for each container, init containers included. OpenShell cannot size
  its supervisor and init containers itself, so without it they run with no request. It sizes a pod only at
  admission. It needs `sandboxPolicy.enabled`. Turning it off removes the chart objects and applies nothing new;
  existing LimitRanges stay until you delete them (`kubectl delete limitrange -A -l koinon.dev/sandbox-limit-range=true`).

Failed applies show in `koinon_reconciler_sandbox_network_policy_errors_total` and
`koinon_reconciler_sandbox_limit_range_errors_total`
([Metrics](/docs/operate/metrics/)). A LimitRange error holds that org's sandbox work.

## How fast sandboxes start

An org may create or start at most 10 sandboxes a minute by default, so a burst of schedules queues instead of
overloading the node. Change it with `koinon-api org-limits set --sandbox-creations-per-minute`
([Back up and restore](/docs/operate/backup-restore/#check-the-result-held) shows the command). A held agent
shows the phase `WaitingForCreationRate`; its runs wait and the next pass retries.
