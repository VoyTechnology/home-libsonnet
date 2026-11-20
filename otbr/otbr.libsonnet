local k = import 'k.libsonnet';

// OpenThread Border Router (ghcr.io/ownbee/hass-otbr-docker) as a single-replica StatefulSet on the host
// network with a Thread radio passed through, plus a Service for its REST API and web UI. Customise it by
// mixing into the hidden fields: `otbr_env`, `otbr_container`, `volumes`, `pod_spec`.
{
  local cfg = $._config,
  local name = cfg.name,

  // Immutable. Never change these.
  local selector = { app: 'otbr', name: 'otbr' },
  local labels = selector,

  // Environment as a map of variable to value. Rendered sorted by name.
  otbr_env:: {
    DEVICE: cfg.threadDongle,
    BACKBONE_IF: cfg.networkInterface,
    BAUDRATE: '460800',
    FLOW_CONTROL: '0',
    FIREWALL: '1',
    NAT64: '1',
    AUTOFLASH_FIRMWARE: '0',
    OTBR_REST_PORT: std.toString(cfg.restPort),
    OTBR_WEB_PORT: std.toString(cfg.webPort),
  },

  // Pod volumes by name, as the volume source. `data` comes from the volumeClaimTemplate.
  volumes:: {
    'thread-dongle': { hostPath: { path: cfg.threadDongle } },
    tun: { hostPath: { path: '/dev/net/tun' } },
  },

  otbr_container:: {
    name: 'otbr',
    image: $._images.otbr,
    env: [{ name: k, value: $.otbr_env[k] } for k in std.sort(std.objectFields($.otbr_env))],
    securityContext: { privileged: true },
    volumeMounts: [
      { name: 'thread-dongle', mountPath: cfg.threadDongle },
      { name: 'tun', mountPath: '/dev/net/tun' },
      { name: 'data', mountPath: '/data' },
    ],
  },

  // The pod spec without the containers and volumes. Extend it, e.g. `pod_spec+:: { tolerations: [...] }`.
  pod_spec:: {
    hostNetwork: true,
    dnsPolicy: 'ClusterFirstWithHostNet',
    nodeSelector: { 'kubernetes.io/hostname': cfg.nodeName },
  },

  otbrStatefulSet:
    local s = k.apps.v1.statefulSet;
    local pvc = k.core.v1.persistentVolumeClaim;
    // The pod spec mixin goes first so the library's containers and volumes always win.
    { spec+: { template+: { spec+: $.pod_spec } } }
    + s.new(
      name,
      1,
      [$.otbr_container],
      [
        pvc.metadata.withName('data')
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
    // The Thread network credentials live on the volume.
    + s.spec.persistentVolumeClaimRetentionPolicy.withWhenDeleted('Retain') + s.spec.persistentVolumeClaimRetentionPolicy.withWhenScaled('Retain')
    + s.spec.template.spec.withVolumes([{ name: n } + $.volumes[n] for n in std.objectFields($.volumes)]),

  otbrService:
    local svc = k.core.v1.service;
    local port = k.core.v1.servicePort;
    svc.new(name, { app: 'otbr' }, [
      port.withName('rest-api') + port.withPort(cfg.restPort) + port.withTargetPort(cfg.restPort) + port.withProtocol('TCP'),
      port.withName('web') + port.withPort(cfg.webPort) + port.withTargetPort(cfg.webPort) + port.withProtocol('TCP'),
    ])
    + svc.metadata.withLabels(labels)
    + svc.spec.withType('ClusterIP'),
}
