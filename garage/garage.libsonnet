// Garage (https://garagehq.deuxfleurs.fr), a small S3-compatible object store, as a single replica:
// one StatefulSet with a metadata and a data volume, the S3/admin Service and its config.
// The secrets (RPC secret, admin token) come from a Secret as environment variables, never the config.
{
  local cfg = $._config,
  local ns = cfg.namespace,
  local name = cfg.name,
  local version = std.reverse(std.split($._images.garage, ':'))[0],

  // Selectors are immutable. Never change these.
  local selector = {
    'app.kubernetes.io/name': name,
    'app.kubernetes.io/instance': name,
  },
  local labels = selector {
    'app.kubernetes.io/version': std.lstripChars(version, 'v'),
    'app.kubernetes.io/managed-by': 'Tanka',
  },
  local meta(component=null) = {
    name: name,
    namespace: ns,
    labels: labels,
  },

  garageNamespace: if cfg.createNamespace then {
    apiVersion: 'v1',
    kind: 'Namespace',
    metadata: { name: ns },
  } else {},

  garageConfigMap: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: meta(),
    data: {
      'garage.toml': |||
        metadata_dir = "/var/lib/garage/meta"
        data_dir = "/var/lib/garage/data"
        db_engine = "lmdb"
        replication_factor = %(replication)d

        rpc_bind_addr = "[::]:3901"

        [s3_api]
        api_bind_addr = "[::]:3900"
        s3_region = "%(region)s"

        [admin]
        api_bind_addr = "[::]:3903"
      ||| % { replication: cfg.replicationFactor, region: cfg.region },
    },
  },

  garageService: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: meta(),
    spec: {
      type: 'ClusterIP',
      ports: [
        { name: 's3', port: 3900, targetPort: 's3', protocol: 'TCP' },
        { name: 'rpc', port: 3901, targetPort: 'rpc', protocol: 'TCP' },
        { name: 'admin', port: 3903, targetPort: 'admin', protocol: 'TCP' },
      ],
      selector: selector,
    },
  },

  // The container. Extend it with a mixin, e.g. `garage_container+:: { env+: [...] }`.
  garage_container:: {
    local secretEnv(var, key) = { name: var, valueFrom: { secretKeyRef: { name: cfg.secretName, key: key } } },
    name: 'garage',
    image: $._images.garage,
    imagePullPolicy: 'IfNotPresent',
    env: [
      secretEnv('GARAGE_RPC_SECRET', 'rpc-secret'),
      secretEnv('GARAGE_ADMIN_TOKEN', 'admin-token'),
    ],
    ports: [
      { name: 's3', containerPort: 3900, protocol: 'TCP' },
      { name: 'rpc', containerPort: 3901, protocol: 'TCP' },
      { name: 'admin', containerPort: 3903, protocol: 'TCP' },
    ],
    // The admin /health only passes once a layout exists, which the bootstrap Job applies through the Service.
    readinessProbe: { tcpSocket: { port: 'admin' }, periodSeconds: 10 },
    livenessProbe: { tcpSocket: { port: 'admin' }, initialDelaySeconds: 15, periodSeconds: 30 },
    volumeMounts: [
      { name: 'config', mountPath: '/etc/garage.toml', subPath: 'garage.toml' },
      { name: 'meta', mountPath: '/var/lib/garage/meta' },
      { name: 'data', mountPath: '/var/lib/garage/data' },
    ],
  } + (if std.length(cfg.resources) > 0 then { resources: cfg.resources } else {}),

  garageStatefulSet: {
    local claim(volume, size) = {
      metadata: { name: volume },
      spec: {
        accessModes: ['ReadWriteOnce'],
        resources: { requests: { storage: size } },
      } + (if cfg.storageClassName != null then { storageClassName: cfg.storageClassName } else {}),
    },
    apiVersion: 'apps/v1',
    kind: 'StatefulSet',
    metadata: meta(),
    spec: {
      serviceName: name,
      replicas: 1,
      selector: { matchLabels: selector },
      template: {
        metadata: {
          labels: selector,
          // Garage serves Prometheus metrics on the admin port.
          annotations: { 'prometheus.io/scrape': 'true', 'prometheus.io/port': '3903' },
        },
        spec: {
          containers: [$.garage_container],
          volumes: [{ name: 'config', configMap: { name: name } }],
        },
      },
      volumeClaimTemplates: [claim('meta', cfg.metaSize), claim('data', cfg.dataSize)],
    },
  },
}
