// Overrides: another namespace and name, no CRDs, scheduling and sizing.
local es = (import '../../../main.libsonnet') {
  _config+:: {
    name: 'eso',
    namespace: 'kube-system',
    installCRDs: false,
    replicas+: { controller: 2 },
    resources: { controller: { requests: { cpu: '10m' } } },
    nodeSelector: { role: 'infra' },
    extraArgs+: { controller: ['--enable-leader-election'] },
  },
};

assert es.esCrds == {};
assert es.esDeployment.metadata.name == 'eso';
assert es.esDeployment.metadata.namespace == 'kube-system';
assert es.esDeployment.spec.replicas == 2;
assert es.esDeployment.spec.template.spec.nodeSelector == { role: 'infra' };
assert es.esDeployment.spec.template.spec.containers[0].resources.requests.cpu == '10m';
assert std.member(es.esDeployment.spec.template.spec.containers[0].args, '--enable-leader-election');
// The cert-controller finds the webhook by the names derived from `name`.
assert std.member(es.esCertControllerDeployment.spec.template.spec.containers[0].args, '--service-name=eso-webhook');
assert es.esSecretStoreWebhook.webhooks[0].clientConfig.service.namespace == 'kube-system';
es
