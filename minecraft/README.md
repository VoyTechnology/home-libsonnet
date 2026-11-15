# minecraft

A [Minecraft server](https://github.com/itzg/docker-minecraft-server) as a single-replica StatefulSet with
one Service per port and an optional [mc-backup](https://github.com/itzg/docker-mc-backup) sidecar that
tars the world once a day. Nothing is a values dump: the server is configured by mixing into hidden fields.

```jsonnet
local mc = import 'minecraft/main.libsonnet';

mc {
  minecraft_env+:: { TYPE: 'PAPER', MOTD: 'Welcome' },
  ports+:: { bedrock: { port: 19132, protocol: 'UDP', serviceType: 'LoadBalancer' } },
  pod_spec+:: { nodeSelector: { 'kubernetes.io/hostname': 'node' } },
  minecraft_container+:: { volumeMounts+: [{ name: 'config', mountPath: '/config' }] },
  volumes+:: { config: { configMap: { name: 'extra-config' } } },
}
```

| Hidden field | What |
| --- | --- |
| `minecraft_env` / `backup_env` | Environment as `NAME: value`; an object value is a `valueFrom` |
| `ports` | Ports by name; one with `serviceType` also gets a Service (`minecraft` keeps `<name>`) |
| `volumes` | Pod volumes by name; mount them from a container mixin |
| `minecraft_container` / `backup_container` | The containers, for anything else |
| `pod_spec` | Pod spec without containers and volumes (node selector, tolerations, ...) |

The RCON password is read from the Secret `rconSecretName` (key `rconSecretKey`); no Secret is rendered
here. The data PVC is the `datadir` volume claim template. The backups land in an emptyDir, so copy them out
with `backup_env+:: { POST_BACKUP_SCRIPT: '...' }` and a volume. Options are in
[config.libsonnet](config.libsonnet), images in [images.libsonnet](images.libsonnet).
