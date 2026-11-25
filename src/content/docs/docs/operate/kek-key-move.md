---
title: Move the key that wraps the KEKs
description: Change the KMS key that wraps the key-encryption keys, with a read-only old key during the move.
area: security-audit
tags: [secrets, encryption]
audience: [operator]
---

Use this page when the KMS key that wraps your key-encryption keys (KEKs) must change. Examples:
a new OpenBao transit key, a new AWS KMS key, or a move from a KMS back to local KEKs.

## How it works

- The chart gives each pod a **primary** key and, during a move, a **read-only** key.
- The read-only key is the old key. It only decrypts. Nothing new is ever wrapped with it.
- koinon-api and the reconciler open each KEK with the key that wrapped it.
- If neither key opens a KEK, the load fails. Koinon does not guess (fail closed).
- The key-admin Job is the only identity that encrypts. It always uses the primary key.

## Before you start

1. Make a backup of the KEK Secret and of the database.
2. Make the new key. The new key MUST have another name or ARN than the old key.
   Koinon stores the key name with each wrapped KEK. It uses the name to find the key.
3. Give each identity access to the new key:
   - OpenBao: `update` on `<transitMount>/decrypt/<key>` for the koinon-api and reconciler roles.
     Add `update` on `<transitMount>/encrypt/<key>` for the key-admin role. Never grant `create`.
   - AWS KMS: `kms:Decrypt` for koinon-api and the reconciler. Add `kms:Encrypt` for key-admin.
4. Keep the access to the old key. Each identity must still decrypt with it.

## Steps

1. Put the old key in `secrets.kek.kms.readOnly`. Put the new key in `secrets.kek.kms`.
   OpenBao example:

   ```yaml
   secrets:
     kek:
       kms:
         backend: openbao
         openbao:
           address: https://bao.example:8200
           key: koinon-kek-2027        # the new key
         readOnly:
           backend: openbao
           openbao:
             address: https://bao.example:8200
             key: koinon-kek           # the old key
         keyAdmin:
           addKey: kek-20270101-a1b2   # a new KEK ID
   ```

   AWS KMS example: set `readOnly.backend: awskms` with `readOnly.awskms.region` and `readOnly.awskms.keyId`.
   To move back to local KEKs, set `backend: local` and keep the old KMS key in `readOnly`.
2. Run `helm upgrade`. The key-admin Job adds the new KEK. The new KEK is wrapped with the primary key.
3. In koinon-api, run `keys status`. It shows a warning while the active KEK is wrapped only by the
   read-only key:

   ```
   WARNING: the active KEK ... is still wrapped only by the read-only key (...)
   ```

4. Run `keys activate <new KEK ID>`.
5. Run `keys rewrap`. It moves each stored value to the active KEK.
6. Run `keys retire` for the old KEKs. Run `keys status` again.
7. When `keys status` shows no warning and no value uses an old KEK, remove `secrets.kek.kms.readOnly`
   from your values. Run `helm upgrade` again.
8. Keep the old KMS key until your backups that need it are out of date. Then you can delete it.

## What the health check shows

- `keys status` prints the warning above. The reconciler and koinon-api write the same warning to the log.
  They repeat it every 10 minutes.
- The warning stops when the primary key wraps the active KEK.
- A KEK that neither key opens is not a warning. It is a load error. Restore the key or the KEK Secret.

## Errors

- `the key-wrapping key ... is configured twice`: the read-only key has the same name as the primary.
  Use another key name or ARN.
- `--read-only-kek-backend=local`: the read-only key is a KMS key. A local KEK always opens.
- `no adapter is configured for the key-wrapping key ...`: a stored KEK names a key that is not the
  primary and not the read-only key. Add that key as the read-only key, or restore the right Secret.
