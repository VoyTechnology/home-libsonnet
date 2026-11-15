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

  otbrStatefulSet: {
    apiVersion: 'apps/v1',
    kind: 'StatefulSet',
    metadata: { name: name, labels: labels },
    spec: {
      serviceName: name,
      replicas: 1,
      selector: { matchLabels: selector },
      // The Thread network credentials live on the volume.
      persistentVolumeClaimRetentionPolicy: { whenDeleted: 'Retain', whenScaled: 'Retain' },
      template: {
        metadata: { labels: labels },
        spec: $.pod_spec {
          containers: [$.otbr_container],
          volumes: [{ name: n } + $.volumes[n] for n in std.objectFields($.volumes)],
        },
      },
      volumeClaimTemplates: [{
        metadata: { name: 'data' },
        spec: {
          accessModes: ['ReadWriteOnce'],
          resources: { requests: { storage: cfg.dataStorageSize } },
        } + (if cfg.dataStorageClass != null then { storageClassName: cfg.dataStorageClass } else {}),
      }],
    },
  },

  otbrService: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: { name: name, labels: labels },
    spec: {
      type: 'ClusterIP',
      ports: [
        { name: 'rest-api', port: cfg.restPort, targetPort: cfg.restPort, protocol: 'TCP' },
        { name: 'web', port: cfg.webPort, targetPort: cfg.webPort, protocol: 'TCP' },
      ],
      selector: { app: 'otbr' },
    },
  },
}
