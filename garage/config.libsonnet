{
  _config+:: {
    namespace: 'garage',
    // Render the Namespace too. Leave off for namespaces managed elsewhere.
    createNamespace: false,

    // Name of every object, and of the Service the S3 API is reached at.
    name: 'garage',

    // Region the S3 API reports. Clients must use the same one.
    region: 'garage',
    // Garage stores everything once (single node): no redundancy besides the disk's.
    replicationFactor: 1,

    // PVCs of the single replica. storageClassName null is the cluster default.
    storageClassName: null,
    metaSize: '1Gi',
    dataSize: '20Gi',
    // Capacity (bytes) given to the node in the layout. Only matters for balancing across nodes.
    layoutCapacity: 20 * 1000 * 1000 * 1000,

    // Secret holding the `rpc-secret` (hex, `openssl rand -hex 32`) and `admin-token` keys.
    secretName: 'garage',
    // Secret holding the S3 key to import: `access-key-id` (GK + 24 hex chars) and `secret-access-key` (64 hex chars).
    s3KeySecretName: 'garage-s3-key',
    // Buckets the bootstrap Job creates, with read/write for the imported key.
    buckets: [],

    resources: {},
  },
}
