# matter-server

[Matter Server](https://github.com/matter-js/matterjs-server) as a single-replica StatefulSet on the host
network, with a Service and ServiceAccount. Home Assistant connects to it as its Matter controller.

```jsonnet
local matter = import 'matter-server/main.libsonnet';

matter {
  _config+:: { networkInterface: 'eth0', dataStorageClass: 'longhorn' },
  matter_container+:: { args+: ['--vendorid', '4939'] },
}
```

| Hidden field | What |
| --- | --- |
| `matter_container` | The container (args, probes, security context) |
| `volumes` | Pod volumes (`tmp`) as the volume source |
| `pod_spec` | Pod spec without containers and volumes |

The commissioned devices live on the `data-<name>-0` claim from the volumeClaimTemplate. Options are in
[config.libsonnet](config.libsonnet), images in [images.libsonnet](images.libsonnet).
