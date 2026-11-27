local k = import 'k.libsonnet';

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
  // The labels and namespace for an object of the type `t`, e.g. `k.apps.v1.statefulSet`.
  local meta(t) = t.metadata.withNamespace(ns) + t.metadata.withLabels(labels),

  garageNamespace: if cfg.createNamespace then k.core.v1.namespace.new(ns) else {},

  garageConfigMap:
    k.core.v1.configMap.new(name, {
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
    })
    + meta(k.core.v1.configMap),

  garageService:
    local svc = k.core.v1.service;
    local port = k.core.v1.servicePort;
    svc.new(name, selector, [
      port.withName('s3') + port.withPort(3900) + port.withTargetPort('s3') + port.withProtocol('TCP'),
      port.withName('rpc') + port.withPort(3901) + port.withTargetPort('rpc') + port.withProtocol('TCP'),
      port.withName('admin') + port.withPort(3903) + port.withTargetPort('admin') + port.withProtocol('TCP'),
    ])
    + meta(svc)
    + svc.spec.withType('ClusterIP'),

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

  garageStatefulSet:
    local s = k.apps.v1.statefulSet;
    local pvc = k.core.v1.persistentVolumeClaim;
    local claim(volume, size) =
      pvc.metadata.withName(volume)
      + pvc.spec.withAccessModes(['ReadWriteOnce'])
      + pvc.spec.resources.withRequests({ storage: size })
      + (if cfg.storageClassName != null then pvc.spec.withStorageClassName(cfg.storageClassName) else {});
    s.new(name, 1, [$.garage_container], [claim('meta', cfg.metaSize), claim('data', cfg.dataSize)])
    + meta(s)
    + s.spec.withServiceName(name)
    // new() would add a `name` label; the selector is immutable and must stay as it was.
    + s.spec.selector.withMatchLabels(selector)
    + s.spec.template.metadata.withLabels(selector)
    // Garage serves Prometheus metrics on the admin port.
    + s.spec.template.metadata.withAnnotations({ 'prometheus.io/scrape': 'true', 'prometheus.io/port': '3903' })
    + s.spec.template.spec.withVolumes([{ name: 'config', configMap: { name: name } }]),
}
