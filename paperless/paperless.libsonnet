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
  local meta(n) = { name: n, namespace: cfg.namespace, labels: labels },

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

  paperlessNamespace: if cfg.createNamespace then {
    apiVersion: 'v1',
    kind: 'Namespace',
    metadata: { name: cfg.namespace },
  } else {},

  paperlessDeployment: {
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: meta(name),
    spec: {
      replicas: cfg.replicas,
      selector: { matchLabels: selector },
      // The data is shared through the node, so never run two pods at once.
      strategy: { type: 'Recreate' },
      template: {
        metadata: { labels: labels },
        spec: $.pod_spec {
          containers: [$.paperless_container, $.redis_container],
          volumes: [{ name: n } + $.volumes[n] for n in std.objectFields($.volumes)],
        },
      },
    },
  },

  paperlessService: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: meta(name),
    spec: {
      type: 'ClusterIP',
      ports: [{ name: 'http', port: $.port, targetPort: $.port, protocol: 'TCP' }],
      selector: selector,
    },
  },
}
