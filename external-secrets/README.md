# external-secrets

The [External Secrets Operator](https://external-secrets.io): controller, webhook and
cert-controller Deployments, their RBAC, the webhook Service/Secret/
ValidatingWebhookConfigurations and the CRDs. It follows the upstream Helm chart's default
rendering, so no chart is needed. For `ExternalSecret` and `ClusterSecretStore` objects use
[external-secrets-libsonnet](https://github.com/jsonnet-libs/external-secrets-libsonnet).

```jsonnet
local externalSecrets = import 'external-secrets/main.libsonnet';

externalSecrets {
  _config+:: {
    namespace: 'kube-system',
    // Another operator install owns the CRDs?
    // installCRDs: false,
  },
}
```

Use `_config+::` (not `_config::`) so the defaults are kept. All options are in
[config.libsonnet](config.libsonnet): names, namespace (optionally rendered with
`createNamespace`), image and version, replicas, resources, scheduling and extra args.

Resources are named `<name>`, `<name>-webhook` and `<name>-cert-controller`. The service
account the controller runs as is `esServiceAccount.metadata.name`, which is what a
`ClusterSecretStore` using the `kubernetes` provider should reference.

## CRDs and upgrades

The CRDs are vendored in [crds/](crds) as compact JSON (generated, do not edit) because
Jsonnet cannot fetch them. To upgrade:

```sh
just generate v0.19.0   # needs helm and yq; re-vendors crds/ and crds/VERSION
```

then set `version` in [config.libsonnet](config.libsonnet) to the same value. The default
test fails if the two disagree. Renovate can bump `version`, but the CRDs still need
regenerating in the same PR.

## Tests

`just test` renders `test/environments/*` with rustanka. They check the object set, the
CRD version and that overrides apply. The 19 non-CRD objects were also compared with
`helm template` of chart 0.18.2 and match apart from labels and argument order.
