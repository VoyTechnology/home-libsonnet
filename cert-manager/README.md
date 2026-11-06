# cert-manager

[cert-manager](https://cert-manager.io): controller, webhook and cainjector Deployments,
their RBAC, Services, webhook configurations, NetworkPolicies and the CRDs. The objects are
the upstream Helm chart's default rendering, written out in [operator.libsonnet](operator.libsonnet),
so no chart is needed. For `ClusterIssuer` and `Certificate` objects use
[cert-manager-libsonnet](https://github.com/jsonnet-libs/cert-manager-libsonnet).

```jsonnet
local certManager = import 'cert-manager/main.libsonnet';

certManager {
  controller_container+:: {
    args+: ['--dns01-recursive-nameservers-only'],
  },
}
```

Use `_config+::` (not `_config::`) so the defaults are kept. All options are in
[config.libsonnet](config.libsonnet): namespace (optionally rendered with `createNamespace`),
replicas, resources and scheduling per component. Images (and so the version) are in
[images.libsonnet](images.libsonnet) as `_images`; override them with `_images+::`, which is also
what Renovate bumps in the consuming repo. The containers are the hidden
fields `controller_container`, `cainjector_container` and `webhook_container`: extend them with
a mixin (`args+:`, `env+:`, `resources+:`, ...) for anything the config doesn't cover. Object names are the
chart's (`cert-manager`, `cert-manager-webhook`, `cert-manager-cainjector`), so it can take
over from a Helm install in place. Objects are the `cm*` fields; ClusterRoles and bindings of
the controllers are grouped in `cmControllerClusterRoles` and `cmControllerClusterRoleBindings`.

## CRDs and upgrades

The CRDs are vendored in [crds/](crds) as compact JSON (generated, do not edit) because
Jsonnet cannot fetch them. To upgrade:

```sh
just generate v1.20.0   # needs helm and yq; re-vendors crds/ and crds/VERSION
```

then set the tags in [images.libsonnet](images.libsonnet) to the same value and diff
`helm template cert-manager` of the new chart against the objects in
[operator.libsonnet](operator.libsonnet) for RBAC or argument changes. The default test fails
if the image tags and the CRDs disagree. Bumping `_images` past the vendored CRDs from a consumer
only updates the images, so take minor upgrades here first. The chart's startupapicheck Job (a Helm hook) is left out.

## Tests

`just test` renders `test/environments/*` with rustanka. They check the object set, the CRD
version, the version and namespace on every object and that overrides apply. The 44
non-CRD objects were also compared with `helm template` of chart v1.19.1 and match apart
from labels.
