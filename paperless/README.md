# paperless

[Paperless-ngx](https://docs.paperless-ngx.com) as a single-replica Deployment with a Redis sidecar and a
Service. Nothing is a values dump: it is configured by mixing into hidden fields.

```jsonnet
local paperless = import 'paperless/main.libsonnet';

paperless {
  _config+:: { url: 'https://docs.example.com', hostPath: '/storage/docs', nodeName: 'node' },
  paperless_env+:: { PAPERLESS_OCR_LANGUAGE: 'eng' },
  volumes+:: { media: { persistentVolumeClaim: { claimName: 'media' } } },
  pod_spec+:: { tolerations: [] },
}
```

| Hidden field | What |
| --- | --- |
| `paperless_env` | Environment as `NAME: value`; an object value is a `valueFrom`. Rendered sorted by name |
| `dirs` / `volumes` | The `data`, `media`, `consume`, `export` directories and their pod volumes |
| `paperless_container` / `redis_container` | The containers, for anything else |
| `pod_spec` | Pod spec without containers and volumes |

`PAPERLESS_SECRET_KEY` is read from the Secret `secretKeyName`; no Secret is rendered here. Options are in
[config.libsonnet](config.libsonnet), images in [images.libsonnet](images.libsonnet).
