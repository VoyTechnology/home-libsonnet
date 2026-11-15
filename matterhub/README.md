# matterhub

[Home Assistant Matter Hub](https://github.com/RiDDiX/home-assistant-matter-hub), which exposes Home
Assistant entities as Matter devices, as a single-replica StatefulSet on the host network with a Service.

```jsonnet
local matterhub = import 'matterhub/main.libsonnet';

matterhub {
  _config+:: { nodeName: 'node1', secretName: 'homeassistant-matterhub' },
  matterhub_env+:: { HAMH_MDNS_NETWORK_INTERFACE: 'eth0' },
  matterhub_container+:: { resources: { limits: { memory: '512Mi' } } },
}
```

| Hidden field | What |
| --- | --- |
| `matterhub_env` | `HAMH_*` environment as `NAME: value`; an object value is a `valueFrom`. Rendered sorted by name |
| `matterhub_container` | The container, for anything else |
| `volumes` | Extra pod volumes as the volume source (`data` comes from the volumeClaimTemplate) |
| `pod_spec` | Pod spec without containers and volumes |

The Home Assistant URL and access token are read from the Secret `secretName`; no Secret is rendered here.
Options are in [config.libsonnet](config.libsonnet), images in [images.libsonnet](images.libsonnet).
