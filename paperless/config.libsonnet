{
  _config+:: {
    namespace: 'paperless',
    // Render the Namespace too. Leave off for namespaces managed elsewhere.
    createNamespace: false,

    // Name of the Deployment, Service and the `app` label. The selector is immutable, never change it.
    name: 'paperless',

    // The URL Paperless is reached on, e.g. https://docs.example.com.
    url: 'https://paperless.local',

    replicas: 1,

    // Where the data, media, consume and export directories live. A directory on the node (the node
    // the pod is pinned to) when set, an emptyDir otherwise. Swap `volumes` for a PVC instead.
    hostPath: null,
    // Pin the pod to this node (kubernetes.io/hostname). Needed for hostPath.
    nodeName: null,

    // Secret with PAPERLESS_SECRET_KEY. Never rendered here.
    secretKeyName: 'paperless-secret-key',
    secretKeyKey: 'secretKey',

    // Container resources. Empty leaves them unset.
    resources: {},
    redisResources: {},
  },
}
