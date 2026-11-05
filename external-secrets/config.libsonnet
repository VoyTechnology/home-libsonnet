{
  _config+:: {
    // Prefix for every resource name and the `app.kubernetes.io/instance` label.
    name: 'external-secrets',
    namespace: 'external-secrets',
    // Render the Namespace too. Leave off for existing namespaces such as kube-system.
    createNamespace: false,

    // renovate: datasource=github-releases depName=external-secrets/external-secrets
    // Must match crds/VERSION: run ./generate-crds.sh <version> when bumping.
    version: 'v0.18.2',
    image: 'oci.external-secrets.io/external-secrets/external-secrets',
    imagePullPolicy: 'IfNotPresent',

    // Install the (vendored) CRDs. Turn off if they are managed elsewhere.
    installCRDs: true,

    logLevel: 'info',
    // Concurrent reconciles of the controller.
    concurrent: 1,
    replicas: { controller: 1, webhook: 1, certController: 1 },
    // Per component, e.g. { controller: { requests: { cpu: '10m' } } }.
    resources: {},
    nodeSelector: {},
    tolerations: [],
    // Extra container args per component.
    extraArgs: { controller: [], webhook: [], certController: [] },
  },
}
