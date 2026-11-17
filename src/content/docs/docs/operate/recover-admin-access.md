---
title: Recover admin access
description: Get a platform admin API token or reset a local password without kubectl exec, through a Kubernetes request object that only the requester can read the result of.
area: install-operations
tags: [auth, kubernetes, backup-restore]
audience: [operator]
---

Use this when nobody can sign in as a platform admin: the bootstrap password is lost, OIDC is
down or was configured wrong, or a restored install has no usable session
([Back up and restore](/docs/operate/backup-restore/)). It does not need `kubectl exec` into a
Koinon pod, which a distroless image or a cluster policy may forbid. It works while `koinon-api` is
down and while the install is held. It needs the database.

You create a `PlatformAdminRecovery` object in the release namespace. The reconciler acts on it and
writes the result into the object's status, **sealed to a key that only you hold**. Nobody who can
read Secrets or the object can open it.

## Who may ask

Kubernetes RBAC decides, and nobody may by default. The chart renders a Role
`<release>-platform-recovery` (create, get, list and watch on `platformadminrecoveries`) and binds it to
the subjects in `recovery.subjects`:

```yaml chart-values
recovery:
  enabled: true
  subjects:
    - kind: User
      name: alice@example.com
      apiGroup: rbac.authorization.k8s.io
```

Nothing in the Koinon database grants the right. A native ValidatingAdmissionPolicy that the chart renders
makes sure `spec.requester` and `spec.requesterGroups` are the identity the API server authenticated, and
refuses every change to `spec`, so nobody can ask in another person's name. The reconciler checks that the
policy and its binding are in force before it acts on a request, and refuses the request when they are
missing or changed. `recovery.enabled: false` renders neither the Role nor the policy.

Helm installs the CRD from the chart's `crds/` directory on a first install. Helm never upgrades a CRD, and
one cluster has one CRD for every release. After an upgrade that names a newer CRD, apply it by hand:

```sh
helm pull oci://ghcr.io/stateracloud/koinon/charts/koinon --version <version-without-v> --untar --untardir ./koinon-chart
kubectl apply --server-side -f ./koinon-chart/koinon/crds/
```

(With a local copy of the chart, apply its `crds/` directory.) Use `helm install --skip-crds` where you may not
create CRDs; without the CRD, `kubectl create` of a request fails with "no matches for kind", and the rest of
Koinon works as before. Uninstalling a release leaves the CRD; delete it with
`kubectl delete crd platformadminrecoveries.recovery.koinon.dev` when no release is left.

## Make a key, then ask

Make an [age](https://age-encryption.org) key on your own machine. The private key never leaves it:

```sh
age-keygen -o recovery.key
```

The command prints the public key (`age1...`). Create the request with `kubectl create`, never from a Git
repository. The `nonce` is 16 to 64 characters of `A-Z a-z 0-9 _ -` that you choose, and a nonce works once, ever, so an object that a
GitOps tool or a copy and paste applies again does nothing. The request lives at most `ttl` (default 15
minutes, at most 1 hour), counted from its creation:

```sh
kubectl create -f - <<'EOF'
apiVersion: recovery.koinon.dev/v1alpha1
kind: PlatformAdminRecovery
metadata:
  generateName: recover-
  namespace: koinon
spec:
  action: mint-admin-token
  requester: alice@example.com
  nonce: 4f9c1e7a2b8d4c60a1d3
  recipientPublicKey: age1replacewithyourpublickey
EOF
```

`spec.requester` must be your Kubernetes user name, exactly as the API server knows you
(`kubectl auth whoami`), and `requesterGroups` your groups if you have any. The object is refused otherwise.

| `action` | What it does | Fields |
| --- | --- | --- |
| `mint-admin-token` | Makes a platform admin API token and seals it to your key. The user must be a platform admin; otherwise the request is refused ("the user is not a platform admin"). | `user`: the local login (default: the bootstrap admin). `org`: the slug or ID of the org the token belongs to (default: the default org). `tokenTTL`: at most `24h`, default `24h`. |
| `reset-password` | Sets a one-time password for a local user, makes the next sign-in change it, and revokes all that user's sessions. It never creates a user. | `user`: the local login (default: the bootstrap admin). |

`recipientPublicKey` is required for both. A `mint-admin-token` does not end the user's other sessions. If you
suspect a stolen account, reset its password.

## Read the result

Wait for `Done`:

```sh
kubectl -n koinon get platformadminrecoveries
kubectl -n koinon get platformadminrecovery <name> -o jsonpath='{.status.sealedResult}' > result.age
age -d -i recovery.key result.age
```

The last command prints the token or the one-time password. Use the token as a bearer token against the admin
API, and sign in as the admin. `status.phase` is `Done` or `Refused`, with the reason in `status.reason`. The
reconciler deletes the object after its `ttl`.

Each action is one event in the [install audit](/docs/operate/audit/) (`recovery.mint-admin-token` or
`recovery.reset-password`), with the Kubernetes user and groups, the object's UID and the nonce. The token and
the password are never in the event.
