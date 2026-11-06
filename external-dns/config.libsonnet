{
  _config+:: {
    namespace: 'external-dns',
    // Render the Namespace too. Leave off for namespaces managed elsewhere.
    createNamespace: false,

    // Install the (vendored) CRDs. Turn off if they are managed elsewhere.
    installCRDs: true,

    // DNS provider (--provider) and how records are reconciled (sync deletes, upsert-only does not).
    provider: 'cloudflare',
    policy: 'sync',
    registry: 'txt',
    interval: '1m',
    // Kubernetes objects to read hostnames from (--source).
    sources: ['service', 'ingress'],
    // Extra --annotation-filter, e.g. 'dns.kubernetes.io/exclude notin (true)'. Empty for none.
    annotationFilter: '',
    // Additional container arguments, e.g. ['--txt-owner-id=bet1'].
    extraArgs: [],
    // Container environment, e.g. credentials from a Secret.
    env: [],

    replicas: 1,
    resources: {},
    nodeSelector: {},
    tolerations: [],
  },
}
