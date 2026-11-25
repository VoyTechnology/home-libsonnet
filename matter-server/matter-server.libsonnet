local k = import 'k.libsonnet';

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

  matterServiceAccount:
    k.core.v1.serviceAccount.new(name) + k.core.v1.serviceAccount.metadata.withLabels(labels),

  matterStatefulSet:
    local s = k.apps.v1.statefulSet;
    local pvc = k.core.v1.persistentVolumeClaim;
    // The pod spec mixin goes first so the library's containers and volumes always win.
    { spec+: { template+: { spec+: $.pod_spec } } }
    + s.new(
      name,
      1,
      [$.matter_container],
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
    // The commissioned devices live on the volume and cannot be recreated.
    + s.spec.persistentVolumeClaimRetentionPolicy.withWhenDeleted('Retain')
    + s.spec.persistentVolumeClaimRetentionPolicy.withWhenScaled('Retain')
    + s.spec.template.spec.withVolumes([{ name: n } + $.volumes[n] for n in std.objectFields($.volumes)]),

  matterService:
    local svc = k.core.v1.service;
    local port = k.core.v1.servicePort;
    svc.new(name, selector, [port.withName('http') + port.withPort(cfg.servicePort) + port.withTargetPort('http') + port.withProtocol('TCP')])
    + svc.metadata.withLabels(labels)
    + svc.spec.withType('ClusterIP'),
}
