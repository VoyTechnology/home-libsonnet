# garage

[Garage](https://garagehq.deuxfleurs.fr), a small S3-compatible object store, as a single replica: a
StatefulSet with a metadata and a data volume, a Service (S3 `3900`, RPC `3901`, admin `3903`) and the
config. A one-off Job applies the node layout, imports an S3 key and creates the buckets through the
admin API, and can be re-run safely.

```jsonnet
local garage = import 'garage/main.libsonnet';

garage {
  _config+:: {
    namespace: 'metrics-system',
    buckets: ['mimir'],
    storageClassName: 'longhorn',
  },
}
```

Secrets are never rendered here. Two Secrets must exist in the namespace:

| Secret (`_config`) | Keys |
| --- | --- |
| `secretName` (`garage`) | `rpc-secret` (`openssl rand -hex 32`), `admin-token` (`openssl rand -base64 32`) |
| `s3KeySecretName` (`garage-s3-key`) | `access-key-id` (`GK` + 24 hex chars), `secret-access-key` (64 hex chars) |

Point S3 clients at `http://garage.<namespace>.svc:3900` with region `garage` (`_config.region`), path-style
addressing. Options are in [config.libsonnet](config.libsonnet), the images (Renovate bumps them in the
consuming repo) in [images.libsonnet](images.libsonnet). Extend the containers with mixins on the hidden
fields `garage_container` and `garage_bootstrap_container`.
