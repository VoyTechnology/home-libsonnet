local k = import 'k.libsonnet';

// Home Assistant Matter Hub (ghcr.io/riddix/home-assistant-matter-hub), which exposes Home Assistant
// entities as Matter devices, as a single-replica StatefulSet on the host network with a Service.
// Customise it by mixing into the hidden fields: `matterhub_env`, `matterhub_container`, `volumes`,
// `pod_spec`.
{
  local cfg = $._config,
  local name = cfg.name,

  // Immutable. Never change this.
  local selector = { 'app.kubernetes.io/name': name },
  local labels = selector { 'app.kubernetes.io/component': 'matter-hub' },

  // Environment as a map of variable to value; an object value is a `valueFrom`. Rendered sorted by name.
  // Add, for example, `HAMH_MDNS_NETWORK_INTERFACE` with `matterhub_env+:: { ... }`.
  matterhub_env:: {
    HAMH_HOME_ASSISTANT_URL: { secretKeyRef: { name: cfg.secretName, key: cfg.urlKey } },
    HAMH_HOME_ASSISTANT_ACCESS_TOKEN: { secretKeyRef: { name: cfg.secretName, key: cfg.tokenKey } },
    HAMH_LOG_LEVEL: cfg.logLevel,
    HAMH_HTTP_PORT: std.toString(cfg.port),
  },

  // Pod volumes by name, as the volume source. `data` comes from the volumeClaimTemplate.
  volumes:: {},

  matterhub_container:: {
    name: 'matter-hub',
    image: $._images.matterhub,
    env: [
      { name: k } + (
        if std.isObject($.matterhub_env[k]) then { valueFrom: $.matterhub_env[k] } else { value: $.matterhub_env[k] }
      )
      for k in std.objectFields($.matterhub_env)
    ],
    ports: [{ name: 'http', containerPort: cfg.port, protocol: 'TCP' }],
    volumeMounts: [{ name: 'data', mountPath: '/data' }],
    livenessProbe: { httpGet: { path: '/', port: 'http' }, initialDelaySeconds: 30, periodSeconds: 30 },
    readinessProbe: { httpGet: { path: '/', port: 'http' }, initialDelaySeconds: 10, periodSeconds: 10 },
  },

  // The pod spec without the containers and volumes. Extend it, e.g. `pod_spec+:: { tolerations: [...] }`.
  pod_spec:: {
    // Matter needs the host network for mDNS and IPv6, which leaves cluster DNS to be configured by hand.
    hostNetwork: true,
    dnsPolicy: 'None',
    dnsConfig: {
      nameservers: [cfg.clusterDNS],
      searches: ['default.svc.cluster.local', 'svc.cluster.local', 'cluster.local'],
      options: [{ name: 'ndots', value: '2' }, { name: 'edns0' }],
    },
  } + (if cfg.nodeName != null then {
         nodeSelector: { 'kubernetes.io/hostname': cfg.nodeName },
       } else {}),

  matterhubStatefulSet:
    local s = k.apps.v1.statefulSet;
    local pvc = k.core.v1.persistentVolumeClaim;
    // The pod spec mixin goes first so the library's containers and volumes always win.
    { spec+: { template+: { spec+: $.pod_spec } } }
    + s.new(
      name,
      1,
      [$.matterhub_container],
      [
        pvc.metadata.withName('data')
        + pvc.metadata.withLabels(labels)
        + pvc.spec.withAccessModes(['ReadWriteOnce'])
        + pvc.spec.resources.withRequests({ storage: cfg.dataStorageSize })
        + (if cfg.dataStorageClass != null then pvc.spec.withStorageClassName(cfg.dataStorageClass) else {}),
      ],
    )
    + s.metadata.withLabels(labels)
    + s.spec.withServiceName(name)
    // new() would add a `name` label; the selector is immutable and must stay as it was.
    + s.spec.selector.withMatchLabels(selector)
    + s.spec.template.metadata.withLabels(labels)
    // The configuration lives on the volume.
    + s.spec.persistentVolumeClaimRetentionPolicy.withWhenDeleted('Retain')
    + s.spec.persistentVolumeClaimRetentionPolicy.withWhenScaled('Retain')
    + s.spec.template.spec.withVolumes([{ name: n } + $.volumes[n] for n in std.objectFields($.volumes)]),

  matterhubService:
    local svc = k.core.v1.service;
    local port = k.core.v1.servicePort;
    svc.new(name, selector, [port.withName('http') + port.withPort(cfg.port) + port.withTargetPort('http') + port.withProtocol('TCP')])
    + svc.metadata.withLabels(labels)
    + svc.spec.withType('ClusterIP'),
}
