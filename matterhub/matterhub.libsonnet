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

  matterhubStatefulSet: {
    apiVersion: 'apps/v1',
    kind: 'StatefulSet',
    metadata: { name: name, labels: labels },
    spec: {
      serviceName: name,
      replicas: 1,
      selector: { matchLabels: selector },
      persistentVolumeClaimRetentionPolicy: { whenDeleted: 'Retain', whenScaled: 'Retain' },
      template: {
        metadata: { labels: labels },
        spec: $.pod_spec {
          containers: [$.matterhub_container],
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

  matterhubService: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: { name: name, labels: labels },
    spec: {
      type: 'ClusterIP',
      ports: [{ name: 'http', port: cfg.port, targetPort: 'http', protocol: 'TCP' }],
      selector: selector,
    },
  },
}
