{
  _config+:: {
    namespace: 'envoy-gateway-system',
    // Render the Namespace too. Leave off for namespaces managed elsewhere.
    createNamespace: false,

    // Install the (vendored) Envoy CRDs. Turn off if they are managed elsewhere.
    installCRDs: true,

    // Run the certgen Job that creates the control plane TLS Secrets. Needed once on a fresh install;
    // leave off afterwards, since the Job deletes itself and would be recreated on every reconcile.
    certgen: true,
  },
}
