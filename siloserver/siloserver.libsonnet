// Silo (https://siloserver.org) from its omnibus image as a single-replica StatefulSet and a Service.
// PostgreSQL and Redis run inside the container, so there is one volume and nothing else to deploy.
// Customise it with mixins on the hidden fields: `silo_env`, `silo_volumes`, `silo_container`,
// `silo_pod_spec`.
{
  local cfg = $._config.silo,
  local name = cfg.name,

  // The selector and volumeClaimTemplates of a StatefulSet are immutable. Never change these.
  local selector = { 'app.kubernetes.io/name': 'silo' },
  local meta(n) = { name: n, namespace: $._config.namespace, labels: selector },

  // The ports the container always listens on. The Jellyfin and Audiobookshelf ports are the
  // compatibility listeners, which the admin settings can turn off.
  silo_ports:: { http: 8080, jellyfin: 8096, audiobookshelf: 13378 },

  // Environment as a map of variable to value; an object value is a `valueFrom`. Rendered sorted by name.
  envList(env):: [
    { name: k } + (if std.isObject(env[k]) then { valueFrom: env[k] } else { value: std.toString(env[k]) })
    for k in std.sort(std.objectFields(env))
  ],

  silo_env:: {
    PORT: $.silo_ports.http,
    JF_PORT: $.silo_ports.jellyfin,
    ABS_PORT: $.silo_ports.audiobookshelf,
    PUID: cfg.puid,
    PGID: cfg.pgid,
    TZ: cfg.timezone,
    SECRET_KEY: { secretKeyRef: { name: cfg.secretName, key: cfg.secretKey } },
  },

  // Pod volumes by name, as the volume source. `config` is the claim below. Replace `media` with the
  // real source, e.g. `silo_volumes+:: { media: { nfs: { server: 's1', path: '/storage' } } }`.
  silo_volumes:: {
    media: { emptyDir: {} },
    // Transcode segments and prepared downloads. Scratch space, not worth backing up.
    transcode: { emptyDir: {} },
    downloads: { emptyDir: {} },
  },

  silo_container:: {
    name: 'silo',
    image: $._images.silo,
    env: $.envList($.silo_env),
    ports: [
      { name: n, containerPort: $.silo_ports[n], protocol: 'TCP' }
      for n in std.objectFields($.silo_ports)
    ],
    volumeMounts: [
      { name: 'config', mountPath: '/config' },
      { name: 'media', mountPath: cfg.mediaPath, readOnly: true },
      { name: 'transcode', mountPath: '/tmp/silo-transcode' },
      { name: 'downloads', mountPath: '/tmp/silo-download-artifacts' },
    ],
    // Startup covers the first PostgreSQL initialisation and migrations after an update.
    startupProbe: {
      httpGet: { path: '/api/v1/health', port: 'http' },
      periodSeconds: 10,
      failureThreshold: 60,
    },
    readinessProbe: {
      httpGet: { path: '/api/v1/health', port: 'http' },
      periodSeconds: 10,
    },
  } + (if std.length(cfg.resources) > 0 then { resources: cfg.resources } else {}),

  // The pod spec without the containers and volumes. Extend it, e.g. `silo_pod_spec+:: { tolerations: [...] }`.
  silo_pod_spec:: {
    // On stop Silo keeps serving briefly, finishes requests and then stops PostgreSQL.
    terminationGracePeriodSeconds: 120,
  },

  siloStatefulSet: {
    apiVersion: 'apps/v1',
    kind: 'StatefulSet',
    metadata: meta(name),
    spec: {
      replicas: 1,
      serviceName: name,
      selector: { matchLabels: selector },
      template: {
        metadata: { labels: selector },
        spec: $.silo_pod_spec {
          containers: [$.silo_container],
          volumes: [{ name: n } + $.silo_volumes[n] for n in std.objectFields($.silo_volumes)],
        },
      },
      volumeClaimTemplates: [{
        metadata: { name: 'config' },
        spec: {
          accessModes: ['ReadWriteOnce'],
          resources: { requests: { storage: cfg.storage.size } },
        } + (if cfg.storage.storageClassName != null then { storageClassName: cfg.storage.storageClassName } else {}),
      }],
    },
  },

  siloService: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: meta(name),
    spec: {
      type: 'ClusterIP',
      ports: [
        { name: n, port: $.silo_ports[n], targetPort: n, protocol: 'TCP' }
        for n in std.objectFields($.silo_ports)
      ],
      selector: selector,
    },
  },
}
