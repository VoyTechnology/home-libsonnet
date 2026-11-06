# metallb

[MetalLB](https://metallb.io): the controller Deployment, speaker DaemonSet (with the FRR sidecars),
RBAC, webhook and CRDs. The objects are the upstream Helm chart's rendering (chart 0.15.2),
written out in [operator.libsonnet](operator.libsonnet), so no chart is needed. Names, selectors
and labels are the chart's (`metallb-controller`, `metallb-speaker`, ...), so it can take over from a
Helm install in place and the announced IPs keep working during the switch.

```jsonnet
local metallb = import 'metallb/main.libsonnet';

metallb {
  _config+:: { namespace: 'metallb-system' },
}
```

Use `_config+::` (not `_config::`) so the defaults are kept. Options are in
[config.libsonnet](config.libsonnet). Images are in [images.libsonnet](images.libsonnet) as
`_images`; override them with `_images+::`. The containers are the hidden fields
`metallb_controller_container` and `metallb_speaker_container`: extend them with a mixin for
anything the config doesn't cover. Objects are the `metallb*` fields.

## CRDs and upgrades
`./generate.sh <chart version>` re-vendors the CRDs into [crds](crds) from the chart. When upgrading,
also update the images (the controller/speaker tag is the chart's appVersion) and re-diff
`helm template` against `tk show test/environments/default` for the other objects.
