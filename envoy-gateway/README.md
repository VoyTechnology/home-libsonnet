# envoy-gateway

[Envoy Gateway](https://gateway.envoyproxy.io): the control plane Deployment, Service, RBAC, topology
webhook, an optional certgen Job and the Envoy CRDs. The objects are the upstream `gateway-helm`
chart's rendering (v1.7.0, release name `envoy`), written out in [operator.libsonnet](operator.libsonnet),
so no chart is needed. Names, selectors and labels are the chart's, so it can take over from a Helm
install in place.

```jsonnet
local envoyGateway = import 'envoy-gateway/main.libsonnet';

envoyGateway {
  _config+:: { certgen: false },
  envoy_gateway_config+:: { gatewayAPI: { enabled: ['XListenerSet'] } },
}
```

Use `_config+::` (not `_config::`) so the defaults are kept. Options are in
[config.libsonnet](config.libsonnet). Images are in [images.libsonnet](images.libsonnet) as `_images`;
override them with `_images+::`. The `EnvoyGateway` configuration is the hidden field
`envoy_gateway_config` and the container is `envoy_gateway_container`: extend them with a mixin.
Objects are the `envoyGateway*` fields.

The Gateway API CRDs the chart also ships are not included: k3s installs them (`traefik-crd`).

## CRDs and upgrades
`./generate.sh <chart version>` re-vendors the Envoy CRDs into [crds](crds). When upgrading, also update
the images and re-diff `helm template envoy oci://docker.io/envoyproxy/gateway-helm` against
`tk show test/environments/default` for the other objects.
