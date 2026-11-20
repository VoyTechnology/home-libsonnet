local k = import 'k.libsonnet';

// Donetick (https://donetick.com) as a single-replica Deployment on SQLite, a ConfigMap with its
// selfhosted.yaml, a PVC and a Service. Customise it with mixins on the hidden fields: `donetick_config`,
// `donetick_env`, `volumes`, `donetick_container`, `pod_spec`.
{
  local cfg = $._config,
  local name = cfg.name,

  // Selectors are immutable. Never change these.
  local selector = { 'app.kubernetes.io/name': 'donetick' },
  local meta(n) = { name: n, namespace: cfg.namespace, labels: selector },

  port:: 2021,
  dataDir:: '/data',

  // Environment as a map of variable to value; an object value is a `valueFrom`. Rendered sorted by name.
  envList(env):: [
    { name: k } + (if std.isObject(env[k]) then { valueFrom: env[k] } else { value: std.toString(env[k]) })
    for k in std.sort(std.objectFields(env))
  ],

  // DT_* variables override selfhosted.yaml, which is where secrets go. Add with `donetick_env+:: { ... }`.
  donetick_env:: {
    DT_SQLITE_PATH: $.dataDir + '/donetick.db',
    DT_JWT_SECRET: { secretKeyRef: { name: cfg.secretName, key: 'DT_JWT_SECRET' } },
  },

  // selfhosted.yaml as an object. Extend it with `donetick_config+:: { oauth2: { ... } }`; never put secrets here.
  donetick_config:: {
    name: 'selfhosted',
    is_done_tick_dot_com: false,
    is_user_creation_disabled: true,
    database: { type: 'sqlite', migration: true },
    jwt: { session_time: '168h', max_refresh: '168h' },
    server: {
      port: $.port,
      read_timeout: '10s',
      write_timeout: '10s',
      rate_period: '60s',
      rate_limit: 300,
      cors_allow_origins: [
        'http://localhost:5173',
        'http://localhost:7926',
        // Required for the Android app.
        'https://localhost',
        'capacitor://localhost',
      ],
      serve_frontend: true,
    },
    logging: { level: 'info', encoding: 'json', development: false },
    scheduler_jobs: { due_job: '30m', overdue_job: '3h', pre_due_job: '3h' },
    realtime: {
      enabled: true,
      sse_enabled: true,
      heartbeat_interval: '60s',
      connection_timeout: '120s',
      max_connections: 1000,
      max_connections_per_user: 5,
      event_queue_size: 2048,
      cleanup_interval: '2m',
      stale_threshold: '5m',
      enable_compression: true,
      enable_stats: true,
      allowed_origins: ['*'],
    },
  },

  // Pod volumes by name, as the volume source.
  volumes:: {
    config: { configMap: { name: name + '-config' } },
    data: { persistentVolumeClaim: { claimName: cfg.storage.claimName } },
  },

  donetick_container:: {
    name: 'donetick',
    image: $._images.donetick,
    imagePullPolicy: 'IfNotPresent',
    env: $.envList($.donetick_env),
    ports: [{ name: 'http', containerPort: $.port }],
    volumeMounts: [
      { name: 'config', mountPath: '/config/selfhosted.yaml', subPath: 'selfhosted.yaml' },
      { name: 'data', mountPath: $.dataDir },
    ],
  } + (if std.length(cfg.resources) > 0 then { resources: cfg.resources } else {}),

  // The pod spec without the containers and volumes. Extend it, e.g. `pod_spec+:: { tolerations: [...] }`.
  pod_spec:: {},

  donetickNamespace: if cfg.createNamespace then k.core.v1.namespace.new(cfg.namespace) else {},

  donetickConfigMap:
    k.core.v1.configMap.new(name + '-config', { 'selfhosted.yaml': std.manifestYamlDoc($.donetick_config) })
    + k.core.v1.configMap.metadata.withNamespace(cfg.namespace)
    + k.core.v1.configMap.metadata.withLabels(selector),

  donetickPvc:
    k.core.v1.persistentVolumeClaim.new(cfg.storage.claimName)
    + k.core.v1.persistentVolumeClaim.metadata.withNamespace(cfg.namespace)
    + k.core.v1.persistentVolumeClaim.metadata.withLabels(selector)
    + k.core.v1.persistentVolumeClaim.spec.withAccessModes(['ReadWriteOnce'])
    + k.core.v1.persistentVolumeClaim.spec.resources.withRequests({ storage: cfg.storage.size })
    + (if cfg.storage.storageClassName != null then k.core.v1.persistentVolumeClaim.spec.withStorageClassName(cfg.storage.storageClassName) else {}),

  donetickDeployment:
    local d = k.apps.v1.deployment;
    // The pod spec mixin goes first so the library's containers and volumes always win.
    { spec+: { template+: { spec+: $.pod_spec } } }
    + d.new(name, cfg.replicas, [$.donetick_container])
    + d.metadata.withNamespace(cfg.namespace)
    + d.metadata.withLabels(selector)
    // new() would add a `name` label; the selector is immutable and must stay as it was.
    + d.spec.selector.withMatchLabels(selector)
    + d.spec.template.metadata.withLabels(selector)
    // Restart the pod when the rendered config changes.
    + d.spec.template.metadata.withAnnotations({ 'checksum/config': std.md5($.donetickConfigMap.data['selfhosted.yaml']) })
    // SQLite on a ReadWriteOnce volume: never run two pods at once.
    + d.spec.strategy.withType('Recreate')
    + d.spec.template.spec.withVolumes([{ name: n } + $.volumes[n] for n in std.objectFields($.volumes)]),

  donetickService:
    k.core.v1.service.new(name, selector, [k.core.v1.servicePort.withName('http') + k.core.v1.servicePort.withPort($.port) + k.core.v1.servicePort.withTargetPort('http') + k.core.v1.servicePort.withProtocol('TCP')])
    + k.core.v1.service.metadata.withNamespace(cfg.namespace)
    + k.core.v1.service.metadata.withLabels(selector)
    + k.core.v1.service.spec.withType('ClusterIP'),
}
