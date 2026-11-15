# donetick

[Donetick](https://donetick.com) as a single-replica Deployment on SQLite with a ConfigMap, a PVC and a
Service. Nothing is a values dump: it is configured by mixing into hidden fields.

```jsonnet
local donetick = import 'donetick/main.libsonnet';

donetick {
  _config+:: { host: 'chores.example.com' },
  donetick_env+:: { DT_TELEGRAM_TOKEN: { secretKeyRef: { name: 'secrets', key: 'telegram' } } },
  donetick_config+:: { oauth2+: { name: 'My IdP' } },
  pod_spec+:: { tolerations: [] },
}
```

| Hidden field | What |
| --- | --- |
| `donetick_config` | selfhosted.yaml as an object; secrets never go here |
| `donetick_env` | `DT_*` environment as `NAME: value`; an object value is a `valueFrom`. Rendered sorted by name |
| `volumes` | Pod volumes (`config`, `data`) as the volume source |
| `donetick_container` | The container, for anything else |
| `pod_spec` | Pod spec without containers and volumes |

`DT_JWT_SECRET` is read from the Secret `secretName`; no Secret is rendered here. Options are in
[config.libsonnet](config.libsonnet), images in [images.libsonnet](images.libsonnet).
