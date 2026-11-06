{
  _config+:: {
    namespace: 'pocket-id-operator-system',
    // Render the Namespace too. Leave off when it is managed elsewhere.
    createNamespace: false,

    // Install the (vendored) CRDs. Turn off if they are managed elsewhere.
    installCRDs: true,

    replicas: 1,
    nodeSelector: {},
    tolerations: [],
  },
}
