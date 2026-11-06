# pocket-id-operator

[pocket-id-operator](https://github.com/aclerici38/pocket-id-operator): manager Deployment, RBAC,
metrics Service and the vendored CRDs of a release, written out in [operator.libsonnet](operator.libsonnet)
from its `install.yaml` (which hardcodes the `pocket-id-operator-system` namespace; here it is `_config.namespace`).
`PocketIDInstance`, `PocketIDUserGroup` etc. are left to the consumer as plain objects.

```jsonnet
local op = import 'pocket-id-operator/main.libsonnet';

op {
  _config+:: { namespace: 'pocketid' },
  manager_container+:: { args+: ['--zap-log-level=debug'] },
}
```

Use `_config+::` (not `_config::`). Options are in [config.libsonnet](config.libsonnet); the image (and
so the version) is `_images.operator` in [images.libsonnet](images.libsonnet), bumped by Renovate in the
consumer. Customise the container through the hidden field `manager_container`.

## CRDs and upgrades

The CRDs are vendored in [crds/](crds) as compact JSON (generated, do not edit):

```sh
just generate v0.16.2   # needs curl and yq; re-vendors crds/ and crds/VERSION
```

then set the tag in [images.libsonnet](images.libsonnet) to the same value and compare the RBAC and
Deployment in the release's `install.yaml` with [operator.libsonnet](operator.libsonnet). The default
test fails if the image tag and the CRDs disagree.
