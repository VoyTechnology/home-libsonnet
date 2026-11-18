{
  _config+:: {
    namespace: 'silo',

    silo+: {
      // Name of the StatefulSet and Service. The selector is immutable, never change it.
      name: 'silo',

      // Secret holding SECRET_KEY, the master key for at-rest encryption. Never rendered here. Losing
      // it makes every encrypted secret unrecoverable, and changing it does the same.
      secretName: 'silo-secrets',
      secretKey: 'secret_key',

      // /config holds the bundled PostgreSQL, Redis and Silo's own state.
      storage: { size: '10Gi', storageClassName: null },

      // Where the `media` volume is mounted, read-only. Libraries are stored with this path, so
      // keep it when moving from another server that mounted the same files elsewhere.
      mediaPath: '/mnt/media',

      // The account that runs Silo and reads the media.
      puid: 1000,
      pgid: 1000,
      timezone: 'Etc/UTC',
    },
  },
}
