# Exercise 3.2 - Secrets

*Domain: Configuration. Target: ~10 min. Do not open `solution/` until you have tried.*

## Setup

```bash
kubectl create namespace secret-demo
```

## Tasks

1. In the namespace `secret-demo`, create a generic (`Opaque`) Secret named `db-cred` from literals:
   `username=admin` and `password=S3cr3tP@ss`. Then reveal how Kubernetes actually stores those
   values: print the Secret's `data` and decode the `password` field yourself. Is the stored form
   encrypted, encoded, or both - and what does that mean for anyone who can read the object? (Note:
   TLS material has a dedicated helper, `kubectl create secret tls <name> --cert=… --key=…`, which
   produces a typed `kubernetes.io/tls` Secret; you do not need to create one here.)

2. In the same namespace, create a Pod named `sec-env` (image `busybox:1.36`, command
   `sh -c "echo user=$DB_USER && sleep 3600"`) that consumes `db-cred` as environment variables via
   `secretKeyRef` - map `username` to `DB_USER` and `password` to `DB_PASS`. Confirm the values are
   present inside the container. Where might these env values unintentionally end up being exposed?

3. In the same namespace, create a Pod named `sec-vol` (image `busybox:1.36`, command
   `sh -c "cat /etc/db/username && sleep 3600"`) that mounts `db-cred` as a **read-only** volume at
   `/etc/db`. Confirm each key appears as its own file and that the mount is read-only (try to write
   into it and observe the failure). Given both consumption styles work, why is a mounted Secret often
   considered safer than injecting the same values as environment variables?

## Acceptance criteria

- `db-cred` exists in `secret-demo` as type `Opaque` with keys `username` and `password`; its stored
  values are base64-encoded (decodable back to `admin` / `S3cr3tP@ss`), **not** encrypted.
- `sec-env` is `Running` and exposes `DB_USER=admin` and `DB_PASS=S3cr3tP@ss` in its environment.
- `sec-vol` is `Running` with `/etc/db/username` and `/etc/db/password` present as files; the mount is
  read-only, so writing into `/etc/db` fails.

## Docs you may reference

- [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Managing Secrets using kubectl](https://kubernetes.io/docs/tasks/configmap-secret/managing-secret-using-kubectl/)
