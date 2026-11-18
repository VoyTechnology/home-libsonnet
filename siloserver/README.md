# siloserver

[Silo](https://siloserver.org) from its omnibus image (bundled PostgreSQL and Redis) as a single-replica
StatefulSet with a Service. Nothing is a values dump: it is configured by mixing into hidden fields.

```jsonnet
local silo = import 'siloserver/main.libsonnet';

silo {
  _config+:: { namespace: 'media', silo+: { mediaPath: '/nfs' } },
  silo_volumes+:: {
    media: volume.withName('media') + volume.nfs.withServer('s1') + volume.nfs.withPath('/storage'),
  },
  silo_env+:: { SILO_NET_TCP_CONGESTION: 'off' },
  silo_pod_spec+:: { tolerations: [] },
}
```

| Hidden field | What |
| --- | --- |
| `silo_env` | Environment as `NAME: value`; an object value is an `envVar` (e.g. `envVar.fromSecretRef`). Rendered sorted by name |
| `silo_volumes` | Pod volumes (`media`, `transcode`, `downloads`) by name, each a complete `volume`. `config` is the claim |
| `silo_container` | The container, for anything else (probes, capabilities, devices for transcoding) |
| `silo_pod_spec` | Pod spec without containers and volumes |
| `silo_ports` | Container ports, by name: `http` 8080, `jellyfin` 8096 and `audiobookshelf` 13378 |

`SECRET_KEY` is read from the Secret `silo.secretName`; no Secret is rendered here. Silo refuses to start
without it, and losing or changing it makes the encrypted settings unrecoverable. The `media` volume is
mounted read-only at `silo.mediaPath`, an `emptyDir` until replaced. Sign-in plugins (OIDC, LDAP) and the
rest of the settings are managed in Silo's admin UI and stored in its database.

## Naming

Everything this library adds to the top level is `snake_case`: the rendered resources (`silo_statefulset`,
`silo_service`) and the hidden fields (`silo_env`, `silo_volumes`, `silo_container`, `silo_pod_spec`,
`silo_ports`). The prefix keeps the names unique when an app merges several libraries. A consumer's own
resources follow the same rule (`silo_route`, not `siloRoute`).

Kubernetes kinds are one word, however they are capitalised: `silo_statefulset`, not `silo_stateful_set`
(likewise `daemonset`, `configmap`, `httproute`, `externalsecret`).

Replicas are fixed at one (PostgreSQL and Redis run in the pod on a ReadWriteOnce volume). The recommended
CPU and memory are in [scaling.libsonnet](scaling.libsonnet); they are mixed into `silo_container` with the `container.resources` mixins.
Options are in [config.libsonnet](config.libsonnet), the image in [images.libsonnet](images.libsonnet).
