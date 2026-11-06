{
  _config+:: {
    namespace: 'metallb-system',
    // Render the Namespace too. Leave off for namespaces managed elsewhere.
    createNamespace: false,

    // Install the (vendored) CRDs. Turn off if they are managed elsewhere.
    installCRDs: true,
  },
}
