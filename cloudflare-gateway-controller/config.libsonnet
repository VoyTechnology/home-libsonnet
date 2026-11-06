{
  _config+:: {
    namespace: 'cloudflare-gateway-system',
    // Render the Namespace too. Leave off when it is managed elsewhere.
    createNamespace: false,

    // Install the (vendored) CRDs. Turn off if they are managed elsewhere.
    installCRDs: true,

    // Required. Unique cluster identifier, used to name the Cloudflare resources deterministically.
    clusterName: error 'set _config.clusterName',

    replicas: 1,
    nodeSelector: {},
    tolerations: [],
  },
}
