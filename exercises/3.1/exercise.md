# Exercise 3.1 - ConfigMaps

*Domain: Configuration. Target: ~10 min. Do not open `solution/` until you have tried.*

## Setup

```bash
kubectl create namespace config-demo
```

## Tasks

1. In the namespace `config-demo`, create a single ConfigMap named `app-config` that holds **both**
   literal key/value pairs and the contents of a file. Give it the literals `APP_MODE=production`
   and `LOG_LEVEL=info`, and also load a properties file named
   `app.properties` whose lines are `ui.theme=dark`, `ui.locale=en_GB`, and `feature.beta=true`.
   Create it, then `describe` it to see how the data map is built. How is the file key represented in
   the ConfigMap's `data` compared with the three literal keys?

2. In the same namespace, create a Pod named `cm-env` (image `busybox:1.36`, command
   `sh -c "env | sort && sleep 3600"`) that consumes **every** key of `app-config` as environment
   variables using `envFrom`. Read the running Pod's environment and confirm `APP_MODE` and
   `LOG_LEVEL` are set.

3. In the same namespace, create a Pod named `cm-vol` (image `busybox:1.36`, command
   `sh -c "cat /etc/appcfg/app.properties && sleep 3600"`) that mounts `app-config` as a volume at
   `/etc/appcfg`. Confirm the file `app.properties` appears there with the three properties lines.
   Then edit the ConfigMap (change `feature.beta` to `false`) and re-read the file inside the running
   Pod after ~60 s, and re-read the env var `LOG_LEVEL` in `cm-env`. Which of the two updates in place
   without restarting the Pod, and which does not?

## Acceptance criteria

- `app-config` exists in `config-demo` with three keys: the two literals plus `app.properties`
  (whose value is the whole file).
- `cm-env` is `Running`; `envFrom` injects `APP_MODE` and `LOG_LEVEL` as environment variables.
- `cm-vol` is `Running` and shows the properties file under `/etc/appcfg/`; after editing the
  ConfigMap the **mounted file** updates in place (with a short delay) while the **env var** in
  `cm-env` does **not** until the Pod is recreated.

## Docs you may reference

- [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Configure a Pod to Use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/)
