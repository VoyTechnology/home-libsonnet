{
  _config+:: {
    namespace: 'minecraft',
    // Render the Namespace too. Leave off for namespaces managed elsewhere.
    createNamespace: false,

    // Name of the StatefulSet and prefix of every Service.
    name: 'minecraft',

    replicas: 1,
    // PVC of /data. storageClassName null is the cluster default.
    dataSize: '20Gi',
    storageClassName: null,

    // Secret with the RCON password, shared by the server and the backup sidecar. Never rendered here.
    rconSecretName: 'minecraft-rcon',
    rconSecretKey: 'rcon-password',

    // Run itzg/mc-backup next to the server.
    backup: true,

    // Container resources. Empty leaves them unset.
    resources: { requests: { cpu: '500m', memory: '512Mi' } },
    backupResources: { requests: { cpu: '500m', memory: '512Mi' } },
  },
}
