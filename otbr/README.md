# otbr

[OpenThread Border Router](https://github.com/ownbee/hass-otbr-docker) as a single-replica StatefulSet on the
host network with a Thread radio passed through, plus a Service for its REST API and web UI.

```jsonnet
local otbr = import 'otbr/main.libsonnet';

otbr {
  _config+:: {
    nodeName: 'node1',
    threadDongle: '/dev/serial/by-id/usb-...',
    networkInterface: 'eth0',
  },
  otbr_env+:: { NAT64: '0' },
}
```

| Hidden field | What |
| --- | --- |
| `otbr_env` | Container environment as `NAME: value`. Rendered sorted by name |
| `otbr_container` | The container, for anything else |
| `volumes` | Pod volumes (`thread-dongle`, `tun`) as the volume source |
| `pod_spec` | Pod spec without containers and volumes |

The Thread network credentials live on the `data-<name>-0` claim from the volumeClaimTemplate. Options are in
[config.libsonnet](config.libsonnet), images in [images.libsonnet](images.libsonnet).
