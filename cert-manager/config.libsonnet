{
  _config+:: {
    namespace: 'cert-manager',
    // Render the Namespace too. Leave off for existing namespaces such as kube-system.
    createNamespace: false,

    // Install the (vendored) CRDs. Turn off if they are managed elsewhere.
    installCRDs: true,
    // Restrict the webhook's traffic with the chart's NetworkPolicies.
    webhookNetworkPolicy: true,

    replicas: { controller: 1, webhook: 1, cainjector: 1 },
    // Per component, e.g. { controller: { requests: { cpu: '10m' } } }.
    resources: {},
    nodeSelector: {},
    tolerations: [],
  },
}
