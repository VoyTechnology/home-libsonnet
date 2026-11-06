# external-dns

[external-dns](https://kubernetes-sigs.github.io/external-dns): the Deployment, ServiceAccount,
ClusterRole and binding, Service and CRDs. The objects are the upstream Helm chart's rendering
(chart 1.23.0), written out in [operator.libsonnet](operator.libsonnet), so no chart is needed.
Object names are the chart's (`external-dns`, `external-dns-viewer`), so it can take over from
a Helm install in place.

```jsonnet
local externalDns = import 'external-dns/main.libsonnet';

externalDns {
  _config+:: {
    namespace: 'external-dns-system',
    sources: ['service', 'ingress', 'gateway-httproute'],
    annotationFilter: 'dns.kubernetes.io/exclude notin (true)',
    env: [{ name: 'CF_API_TOKEN', valueFrom: { secretKeyRef: { name: 'cloudflare-secret', key: 'token' } } }],
  },
}
```

Use `_config+::` (not `_config::`) so the defaults are kept. All options are in
[config.libsonnet](config.libsonnet). The image (and so the version) is in
[images.libsonnet](images.libsonnet) as `_images`; override it with `_images+::`, which is also
what Renovate bumps in the consuming repo. The container is the hidden field
`external_dns_container`: extend it with a mixin (`args+:`, `env+:`, ...) for anything the
config doesn't cover. Objects are the `externalDns*` fields.

## CRDs and upgrades

The CRDs are vendored in [crds/](crds) as compact JSON (generated, do not edit) because
Jsonnet cannot fetch them. To upgrade:

```sh
just generate 1.24.0   # needs helm and yq; re-vendors crds/ and crds/VERSION (the chart version)
```

then set the tag in [images.libsonnet](images.libsonnet) to the chart's appVersion and diff
`helm template external-dns` of the new chart against [operator.libsonnet](operator.libsonnet)
for RBAC or argument changes.

## Tests

`just test` renders `test/environments/*` with rustanka. They check the object set, the
namespace on every object and that overrides apply. The objects were also compared with
`helm template` of chart 1.23.0 and match apart from labels.
