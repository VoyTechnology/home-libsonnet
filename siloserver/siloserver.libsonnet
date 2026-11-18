// Silo (https://siloserver.org) from its omnibus image as a single-replica StatefulSet and a Service.
// PostgreSQL and Redis run inside the container, so there is one volume and nothing else to deploy.
// Customise it with mixins on the hidden fields: `silo_env`, `silo_volumes`, `silo_container`,
// `silo_pod_spec`.
local k = import 'github.com/jsonnet-libs/k8s-libsonnet/1.35/main.libsonnet';
local container = k.core.v1.container;
local containerPort = k.core.v1.containerPort;
local envVar = k.core.v1.envVar;
local pvc = k.core.v1.persistentVolumeClaim;
local service = k.core.v1.service;
local servicePort = k.core.v1.servicePort;
local statefulSet = k.apps.v1.statefulSet;
local volume = k.core.v1.volume;
local volumeMount = k.core.v1.volumeMount;

{
  local cfg = $._config.silo,
  local name = cfg.name,

  // The selector and volumeClaimTemplates of a StatefulSet are immutable. Never change these.
  local selector = { 'app.kubernetes.io/name': 'silo' },
  // The labels for an object of the type `t`, e.g. `statefulSet`. The namespace comes from the Tanka environment.
  local meta(t) = t.metadata.withLabels(selector),

  // The ports the container always listens on. The Jellyfin and Audiobookshelf ports are the
  // compatibility listeners, which the admin settings can turn off.
  silo_ports:: { http: 8080, jellyfin: 8096, audiobookshelf: 13378 },

  // Environment as a map of variable to value; an object value is a complete `envVar`, e.g.
  // `envVar.fromSecretRef('NAME', 'secret', 'key')`. Rendered sorted by name.
  env_list(env):: [
    if std.isObject(env[n]) then env[n] else envVar.new(n, std.toString(env[n]))
    for n in std.sort(std.objectFields(env))
  ],

  silo_env:: {
    PORT: $.silo_ports.http,
    JF_PORT: $.silo_ports.jellyfin,
    ABS_PORT: $.silo_ports.audiobookshelf,
    PUID: cfg.puid,
    PGID: cfg.pgid,
    TZ: cfg.timezone,
    SECRET_KEY: envVar.fromSecretRef('SECRET_KEY', cfg.secretName, cfg.secretKey),
  },

  // Pod volumes, keyed by their name. `config` is the claim below. Replace `media` with the real source, e.g.
  // `silo_volumes+:: { media: volume.fromEmptyDir('media') + ... }` or
  // `volume.withName('media') + volume.nfs.withServer('s1') + volume.nfs.withPath('/storage')`.
  silo_volumes:: {
    media: volume.fromEmptyDir('media'),
    // Transcode segments and prepared downloads. Scratch space, not worth backing up.
    transcode: volume.fromEmptyDir('transcode'),
    downloads: volume.fromEmptyDir('downloads'),
  },

  local probe(p) =
    p.httpGet.withPath('/api/v1/health')
    + p.httpGet.withPort('http')
    + p.withPeriodSeconds(10),

  silo_container::
    container.new('silo', $._images.silo)
    + container.withEnv($.env_list($.silo_env))
    + container.withPorts([
      containerPort.newNamed($.silo_ports[n], n)
      for n in std.objectFields($.silo_ports)
    ])
    + container.withVolumeMounts([
      volumeMount.new('config', '/config'),
      volumeMount.new('media', cfg.mediaPath) + volumeMount.withReadOnly(true),
      volumeMount.new('transcode', '/tmp/silo-transcode'),
      volumeMount.new('downloads', '/tmp/silo-download-artifacts'),
    ])
    // Startup covers the first PostgreSQL initialisation and migrations after an update.
    + probe(container.startupProbe) + container.startupProbe.withFailureThreshold(60)
    + probe(container.readinessProbe),

  // The pod spec without the containers and volumes. Extend it, e.g. `silo_pod_spec+:: { tolerations: [...] }`.
  silo_pod_spec:: {
    // On stop Silo keeps serving briefly, finishes requests and then stops PostgreSQL.
    terminationGracePeriodSeconds: 120,
  },

  silo_statefulset:
    statefulSet.new(
      name,
      replicas=1,
      containers=[$.silo_container],
      volumeClaims=[
        pvc.new('config')
        + pvc.spec.withAccessModes(['ReadWriteOnce'])
        + pvc.spec.resources.withRequests({ storage: cfg.storage.size })
        + (if cfg.storage.storageClassName != null then pvc.spec.withStorageClassName(cfg.storage.storageClassName) else {}),
      ],
    )
    + meta(statefulSet)
    + statefulSet.spec.withServiceName(name)
    + statefulSet.spec.selector.withMatchLabels(selector)
    + statefulSet.spec.template.metadata.withLabels(selector)
    + statefulSet.spec.template.spec.withVolumes([
      $.silo_volumes[n]
      for n in std.objectFields($.silo_volumes)
    ])
    + { spec+: { template+: { spec+: $.silo_pod_spec } } },

  silo_service:
    service.new(name, selector, [
      servicePort.newNamed(n, $.silo_ports[n], n)
      for n in std.objectFields($.silo_ports)
    ])
    + meta(service),
}
