# gateway-api

The [Gateway API](https://gateway-api.sigs.k8s.io) CRDs of one upstream release, vendored into
[crds](crds) as JSON and exposed as `gatewayApiCrds` (a map of `CustomResourceDefinition` objects).
The release and channel are in [crds/VERSION](crds/VERSION).

```jsonnet
local gatewayApi = import 'gateway-api/main.libsonnet';

gatewayApi
```

## Upgrades
`./generate.sh <release> [experimental|standard]` re-vendors the CRDs from the release's
`<channel>-install.yaml`. Needs curl and yq.
