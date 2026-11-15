// Matter Server (ghcr.io/matter-js/matterjs-server, formerly the derwitt home-assistant-matter-server
// chart) as a single-replica StatefulSet on the host network, with a Service and ServiceAccount. Customise
// it by mixing into the hidden fields: `matter_container`, `volumes`, `pod_spec`.
{
  local cfg = $._config,
  local name = cfg.name,

  // Immutable. Never change this.
  local selector = {
    'app.kubernetes.io/instance': 'homeassistant',
    'app.kubernetes.io/name': 'matter',
  },
  local labels = selector,

  // Pod volumes by name, as the volume source. `data` comes from the volumeClaimTemplate.
  volumes:: {
    tmp: { emptyDir: {} },
  },

  matter_container:: {
    name: 'matter',
    image: $._images.matterServer,
    args: [
      '--storage-path',
      '/data',
      '--port',
      std.toString(cfg.port),
      '--log-level',
      cfg.logLevel,
      '--primary-interface',
      cfg.networkInterface,
    ],
    env: [{ name: 'MATTER_LOG_FORMAT', value: 'plain' }],
    ports: [{ name: 'http', containerPort: cfg.port, protocol: 'TCP' }],
    livenessProbe: { httpGet: { path: '/health', port: 'http' } },
    readinessProbe: { httpGet: { path: '/health', port: 'http' } },
    securityContext: {
      allowPrivilegeEscalation: true,
      privileged: true,
      readOnlyRootFilesystem: true,
      runAsGroup: 0,
      runAsNonRoot: false,
      runAsUser: 0,
      seccompProfile: { type: 'RuntimeDefault' },
    },
    volumeMounts: [
      { name: 'data', mountPath: '/data' },
      { name: 'tmp', mountPath: '/tmp' },
    ],
  },

  // The pod spec without the containers and volumes. Extend it, e.g. `pod_spec+:: { tolerations: [...] }`.
  pod_spec:: {
    serviceAccountName: name,
    hostNetwork: true,
    hostname: name,
    dnsPolicy: 'ClusterFirstWithHostNet',
    securityContext: {
      fsGroup: 0,
      fsGroupChangePolicy: 'OnRootMismatch',
      runAsGroup: 0,
      runAsNonRoot: false,
      runAsUser: 0,
      seccompProfile: { type: 'RuntimeDefault' },
    },
    // A crashed server leaves lock files behind that stop the next start.
    initContainers: [{
      name: 'lock-remover',
      image: $._images.busybox,
      command: ['/bin/sh', '-c'],
      args: ['rm -f /data/*/matter.lock\n'],
      securityContext: {
        allowPrivilegeEscalation: false,
        privileged: false,
        readOnlyRootFilesystem: true,
        runAsGroup: 0,
        runAsNonRoot: false,
        runAsUser: 0,
        seccompProfile: { type: 'RuntimeDefault' },
      },
      volumeMounts: [{ name: 'data', mountPath: '/data' }],
    }],
  } + (if cfg.nodeName != null then {
         nodeSelector: { 'kubernetes.io/hostname': cfg.nodeName },
       } else {}),

  matterServiceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: { name: name, labels: labels },
  },

  matterStatefulSet: {
    apiVersion: 'apps/v1',
    kind: 'StatefulSet',
    metadata: { name: name, labels: labels },
    spec: {
      serviceName: name,
      replicas: 1,
      selector: { matchLabels: selector },
      // The commissioned devices live on the volume and cannot be recreated.
      persistentVolumeClaimRetentionPolicy: { whenDeleted: 'Retain', whenScaled: 'Retain' },
      template: {
        metadata: { labels: labels },
        spec: $.pod_spec {
          containers: [$.matter_container],
          volumes: [{ name: n } + $.volumes[n] for n in std.objectFields($.volumes)],
        },
      },
      volumeClaimTemplates: [{
        metadata: { name: 'data', labels: labels },
        spec: {
          accessModes: ['ReadWriteOnce'],
          resources: { requests: { storage: cfg.dataStorageSize } },
        } + (if cfg.dataStorageClass != null then { storageClassName: cfg.dataStorageClass } else {}),
      }],
    },
  },

  matterService: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: { name: name, labels: labels },
    spec: {
      type: 'ClusterIP',
      ports: [{ name: 'http', port: cfg.servicePort, targetPort: 'http', protocol: 'TCP' }],
      selector: selector,
    },
  },
}
