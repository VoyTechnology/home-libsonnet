// A Minecraft server (https://github.com/itzg/docker-minecraft-server) as a single-replica StatefulSet,
// with one Service per port. Customise it with mixins on the hidden fields: `minecraft_env`, `ports`,
// `volumes`, `minecraft_container`, `pod_spec`.
{
  local cfg = $._config,
  local name = cfg.name,

  // Selectors are immutable. Never change these.
  local selector = { app: name },
  local labels = selector {
    'app.kubernetes.io/name': 'minecraft',
    'app.kubernetes.io/instance': name,
    'app.kubernetes.io/managed-by': 'Tanka',
  },
  local meta(n) = { name: n, namespace: cfg.namespace, labels: labels },

  // Environment as a map of variable to value; an object value is a `valueFrom`. Used for both containers.
  envList(env):: [
    { name: k } + (if std.isObject(env[k]) then { valueFrom: env[k] } else { value: std.toString(env[k]) })
    for k in std.sort(std.objectFields(env))
  ],

  // Environment of the server. Add to it with `minecraft_env+:: { MOTD: '...', PLUGINS: '...' }`.
  minecraft_env:: {
    EULA: 'true',
    TYPE: 'VANILLA',
    VERSION: 'LATEST',
    SERVER_PORT: $.ports.minecraft.port,
    ENABLE_RCON: 'true',
    RCON_PASSWORD: { secretKeyRef: { name: cfg.rconSecretName, key: cfg.rconSecretKey } },
  },

  // Ports by name. `serviceType` set (LoadBalancer, ClusterIP, ...) gives it a Service `<name>-<port>`,
  // the `minecraft` port keeps the Service `<name>`. Add one with `ports+:: { map: { port: 8100 } }`.
  ports:: {
    minecraft: { port: 25565, protocol: 'TCP', serviceType: 'LoadBalancer' },
    rcon: { port: 25575, protocol: 'TCP', serviceType: 'ClusterIP' },
  },

  // Pod volumes by name, as the volume source. Mount them from a container mixin.
  volumes:: {
    tmp: { emptyDir: {} },
  } + (if cfg.backup then { backupdir: { emptyDir: {} } } else {}),

  minecraft_container:: {
    name: 'minecraft',
    image: $._images.minecraft,
    imagePullPolicy: 'IfNotPresent',
    // The console is attached through `kubectl attach` / rcon-cli.
    tty: true,
    stdin: true,
    env: $.envList($.minecraft_env),
    ports: [
      { name: n, containerPort: $.ports[n].port, protocol: $.ports[n].protocol }
      for n in std.objectFields($.ports)
    ],
    readinessProbe: self.livenessProbe,
    livenessProbe: {
      exec: { command: ['mc-health'] },
      initialDelaySeconds: 30,
      periodSeconds: 5,
      failureThreshold: 20,
    },
    securityContext: {
      allowPrivilegeEscalation: false,
      capabilities: { drop: ['ALL'] },
      readOnlyRootFilesystem: true,
    },
    volumeMounts: [
      { name: 'tmp', mountPath: '/tmp' },
      { name: 'datadir', mountPath: '/data' },
    ] + (if cfg.backup then [{ name: 'backupdir', mountPath: '/backups', readOnly: true }] else []),
  } + (if std.length(cfg.resources) > 0 then { resources: cfg.resources } else {}),

  // The pod spec without the containers. Extend it, e.g. `pod_spec+:: { nodeSelector: {...} }`.
  pod_spec:: {
    terminationGracePeriodSeconds: 30,
    securityContext: {
      runAsUser: 1000,
      runAsGroup: 3000,
      runAsNonRoot: true,
      fsGroup: 2000,
      seccompProfile: { type: 'RuntimeDefault' },
    },
  },

  minecraftNamespace: if cfg.createNamespace then {
    apiVersion: 'v1',
    kind: 'Namespace',
    metadata: { name: cfg.namespace },
  } else {},

  minecraftStatefulSet: {
    apiVersion: 'apps/v1',
    kind: 'StatefulSet',
    metadata: meta(name),
    spec: {
      serviceName: name,
      replicas: cfg.replicas,
      selector: { matchLabels: selector },
      template: {
        metadata: { labels: labels },
        spec: $.pod_spec {
          containers: [$.minecraft_container] + (if cfg.backup then [$.backup_container] else []),
          volumes: [{ name: n } + $.volumes[n] for n in std.objectFields($.volumes)],
        },
      },
      volumeClaimTemplates: [{
        metadata: { name: 'datadir' },
        spec: {
          accessModes: ['ReadWriteOnce'],
          resources: { requests: { storage: cfg.dataSize } },
        } + (if cfg.storageClassName != null then { storageClassName: cfg.storageClassName } else {}),
      }],
    },
  },

  // One Service per port that has a serviceType, named after the port.
  minecraftServices: {
    [n]: {
      local p = $.ports[n],
      local svcName = if n == 'minecraft' then name else name + '-' + n,
      apiVersion: 'v1',
      kind: 'Service',
      metadata: meta(svcName),
      spec: {
        type: p.serviceType,
        ports: [{ name: n, port: p.port, targetPort: n, protocol: p.protocol }],
        selector: selector,
      },
    }
    for n in std.objectFields($.ports)
    if std.objectHas($.ports[n], 'serviceType')
  },
}
