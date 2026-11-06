# cert-manager

[cert-manager](https://cert-manager.io): controller, webhook and cainjector Deployments,
their RBAC, Services, webhook configurations, NetworkPolicies and the CRDs. The objects are
the upstream Helm chart's default rendering, vendored by [generate.sh](generate.sh) and
patched by `_config`, so no chart is needed. For `ClusterIssuer` and `Certificate` objects use
[cert-manager-libsonnet](https://github.com/jsonnet-libs/cert-manager-libsonnet).

```jsonnet
local certManager = import 'cert-manager/main.libsonnet';

certManager {
  _config+:: {
    extraArgs+: { controller: ['--dns01-recursive-nameservers-only'] },
  },
}
```

Use `_config+::` (not `_config::`) so the defaults are kept. All options are in
[config.libsonnet](config.libsonnet): namespace (optionally rendered with `createNamespace`),
version, replicas, resources, scheduling and extra args per component. Object names are the
chart's (`cert-manager`, `cert-manager-webhook`, `cert-manager-cainjector`).

## Upgrades

[rendered.json](rendered.json) and [crds/](crds) are generated (do not edit):

```sh
just generate v1.20.0   # needs helm, yq and jq
```

then set `version` in [config.libsonnet](config.libsonnet) to the same value. The default test
fails if the two disagree. Renovate can bump `version`, but the vendored files still need
regenerating in the same PR. The chart's startupapicheck Job (a Helm hook) is left out.

## Tests

`just test` renders `test/environments/*` with rustanka. They check the object set, the CRD
version, that no namespace placeholder is left and that overrides apply.
