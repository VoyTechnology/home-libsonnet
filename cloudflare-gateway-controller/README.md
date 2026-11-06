# cloudflare-gateway-controller

[cloudflare-gateway-controller](https://github.com/matheuscscp/cloudflare-gateway-controller): a Gateway API
controller that serves Gateways through Cloudflare tunnels. Controller Deployment, RBAC and the vendored CRDs
(`CloudflareGatewayParameters`, `CloudflareGatewayStatus`) of a release, written out in
[controller.libsonnet](controller.libsonnet) from its Helm chart (the project ships no plain manifests).

Not included, left to the consumer: the `GatewayClass`, the Secret it references (`CLOUDFLARE_API_TOKEN`,
`CLOUDFLARE_ACCOUNT_ID`) and the Gateways. The Gateway API CRDs and `safe-upgrades` admission policy the
chart bundles are left out too: whatever provides the Gateway API (v1.5+) owns them.

```jsonnet
local cgc = import 'cloudflare-gateway-controller/main.libsonnet';

cgc {
  _config+:: { namespace: 'cloudflare-gateway-system', clusterName: 'bet1' },
  controller_container+:: { args+: ['--zap-log-level=debug'] },
}
```

Use `_config+::` (not `_config::`). `clusterName` is required. Options are in
[config.libsonnet](config.libsonnet); the image (and so the version) is `_images.controller` in
[images.libsonnet](images.libsonnet), bumped by Renovate in the consumer. The same image runs the tunnels.
Customise the container through the hidden field `controller_container`.

## CRDs and upgrades

The CRDs are vendored in [crds/](crds) as compact JSON (generated, do not edit):

```sh
just generate v0.16.0   # needs git, helm and yq; re-vendors crds/ and crds/VERSION
```

then set the tag in [images.libsonnet](images.libsonnet) to the same value and compare the RBAC and
Deployment in the chart with [controller.libsonnet](controller.libsonnet). The default test fails if the
image tag and the CRDs disagree.
