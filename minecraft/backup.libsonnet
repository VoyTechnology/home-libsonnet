// itzg/mc-backup, a sidecar that tars /data into /backups (an emptyDir) once a day over RCON.
// Copy the archives out of the pod with `backup_env+:: { POST_BACKUP_SCRIPT: '...' }` and a volume mount.
{
  local cfg = $._config,

  backup_env:: {
    SRC_DIR: '/data',
    BACKUP_NAME: 'world',
    INITIAL_DELAY: '2m',
    BACKUP_INTERVAL: '24h',
    PRUNE_BACKUPS_DAYS: '7',
    PAUSE_IF_NO_PLAYERS: 'false',
    SERVER_PORT: $.ports.minecraft.port,
    RCON_HOST: 'localhost',
    RCON_PORT: $.ports.rcon.port,
    RCON_PASSWORD: { secretKeyRef: { name: cfg.rconSecretName, key: cfg.rconSecretKey } },
    RCON_RETRIES: '5',
    RCON_RETRY_INTERVAL: '10s',
    EXCLUDES: '*.jar,cache,logs',
    BACKUP_METHOD: 'tar',
    DEST_DIR: '/backups',
    LINK_LATEST: 'false',
    TAR_COMPRESS_METHOD: 'gzip',
  },

  backup_container:: {
    name: 'mc-backup',
    image: $._images.backup,
    imagePullPolicy: 'IfNotPresent',
    env: $.envList($.backup_env),
    securityContext: {
      allowPrivilegeEscalation: false,
      capabilities: { drop: ['ALL'] },
      readOnlyRootFilesystem: true,
    },
    volumeMounts: [
      { name: 'tmp', mountPath: '/tmp' },
      { name: 'datadir', mountPath: '/data', readOnly: true },
      { name: 'backupdir', mountPath: '/backups' },
    ],
  } + (if std.length(cfg.backupResources) > 0 then { resources: cfg.backupResources } else {}),
}
