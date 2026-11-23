local k = import 'k.libsonnet';

// Paperless-ngx (https://docs.paperless-ngx.com) as a single-replica Deployment with a Redis sidecar as
// task broker, and a Service. Customise it with mixins on the hidden fields: `paperless_env`, `dirs`,
// `volumes`, `paperless_container`, `redis_container`, `pod_spec`.
{
  local cfg = $._config,
  local name = cfg.name,

  // Selectors are immutable. Never change these.
  local selector = { app: name },
  local labels = selector {
    'app.kubernetes.io/name': 'paperless',
    'app.kubernetes.io/instance': name,
    'app.kubernetes.io/managed-by': 'Tanka',
  },
  // The labels and namespace for an object of the type `t`, e.g. `k.apps.v1.deployment`.
  local meta(t) = t.metadata.withNamespace(cfg.namespace) + t.metadata.withLabels(labels),

  // Environment as a map of variable to value; an object value is a `valueFrom`. Rendered sorted by name,
  // and `$(VAR)` references in a value only expand variables listed before it.
  envList(env):: [
    { name: k } + (if std.isObject(env[k]) then { valueFrom: env[k] } else { value: std.toString(env[k]) })
    for k in std.sort(std.objectFields(env))
  ],

  // Environment of Paperless. Add to it with `paperless_env+:: { PAPERLESS_OCR_LANGUAGE: 'eng' }`.
  paperless_env:: {
    PAPERLESS_URL: cfg.url,
    PAPERLESS_REDIS: 'redis://localhost:6379',
    PAPERLESS_SECRET_KEY: { secretKeyRef: { name: cfg.secretKeyName, key: cfg.secretKeyKey } },
  },

  port:: 8000,

  // Directories under /usr/src/paperless, each its own volume of the same name.
  dirs:: ['data', 'media', 'consume', 'export'],

  // Pod volumes by name, as the volume source. Replace one with `volumes+:: { media: { persistentVolumeClaim: ... } }`.
  volumes:: {
    [d]: if cfg.hostPath != null
    then { hostPath: { path: '%s/%s' % [cfg.hostPath, d], type: 'DirectoryOrCreate' } }
    else { emptyDir: {} }
    for d in $.dirs
  },

  paperless_container:: {
    name: 'paperless',
    image: $._images.paperless,
    imagePullPolicy: 'IfNotPresent',
    env: $.envList($.paperless_env),
    ports: [{ name: 'http', containerPort: $.port }],
    readinessProbe: {
      // Django rejects the pod IP as a Host, so send the host from the URL.
      httpGet: {
        path: '/',
        port: $.port,
        httpHeaders: [{ name: 'Host', value: std.split(cfg.url, '/')[2] }],
      },
      initialDelaySeconds: 30,
    },
    volumeMounts: [{ name: d, mountPath: '/usr/src/paperless/' + d } for d in $.dirs],
  } + (if std.length(cfg.resources) > 0 then { resources: cfg.resources } else {}),

  // Task broker; nothing worth persisting.
  redis_container:: {
    name: 'redis',
    image: $._images.redis,
    imagePullPolicy: 'IfNotPresent',
    ports: [{ containerPort: 6379 }],
  } + (if std.length(cfg.redisResources) > 0 then { resources: cfg.redisResources } else {}),

  // The pod spec without the containers and volumes. Extend it, e.g. `pod_spec+:: { tolerations: [...] }`.
  pod_spec:: {
    // Service links would inject PAPERLESS_PORT=tcp://..., which clashes with Paperless's own setting.
    enableServiceLinks: false,
  } + (if cfg.nodeName != null then { nodeSelector: { 'kubernetes.io/hostname': cfg.nodeName } } else {}),

  paperlessNamespace: if cfg.createNamespace then k.core.v1.namespace.new(cfg.namespace) else {},

  paperlessDeployment:
    local d = k.apps.v1.deployment;
    // The pod spec mixin goes first so the library's containers and volumes always win.
    { spec+: { template+: { spec+: $.pod_spec } } }
    + d.new(name, cfg.replicas, [$.paperless_container, $.redis_container])
    + meta(d)
    // new() would add a `name` label; the selector is immutable and must stay as it was.
    + d.spec.selector.withMatchLabels(selector)
    + d.spec.template.metadata.withLabels(labels)
    // The data is shared through the node, so never run two pods at once.
    + d.spec.strategy.withType('Recreate')
    + d.spec.template.spec.withVolumes([{ name: n } + $.volumes[n] for n in std.objectFields($.volumes)]),

  paperlessService:
    local port = k.core.v1.servicePort;
    k.core.v1.service.new(name, selector, [port.withName('http') + port.withPort($.port) + port.withTargetPort($.port) + port.withProtocol('TCP')])
    + meta(k.core.v1.service)
    + k.core.v1.service.spec.withType('ClusterIP'),
}
