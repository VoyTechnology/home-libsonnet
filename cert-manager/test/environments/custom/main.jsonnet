// Overrides: another namespace and images, no CRDs or network policies, args and sizing.
local cm = (import '../../../main.libsonnet') {
  _config+:: {
    namespace: 'certs',
    createNamespace: true,
    installCRDs: false,
    webhookNetworkPolicy: false,
    replicas+: { controller: 2 },
    resources: { controller: { requests: { cpu: '10m' } } },
    nodeSelector: { role: 'infra' },
  },
  _images+:: {
    controller: 'quay.io/jetstack/cert-manager-controller:v1.20.0',
    acmesolver: 'quay.io/jetstack/cert-manager-acmesolver:v1.20.0',
  },
  controller_container+:: { args+: ['--dns01-recursive-nameservers-only'] },
};

local controller = cm.cmControllerDeployment;
local container = controller.spec.template.spec.containers[0];
assert cm.cmCrds == {};
assert cm.cmWebhookNetworkPolicies == {};
assert cm.cmNamespace.metadata.name == 'certs';
assert controller.metadata.namespace == 'certs';
assert controller.spec.replicas == 2;
assert controller.spec.template.spec.nodeSelector == { 'kubernetes.io/os': 'linux', role: 'infra' };
assert container.resources.requests.cpu == '10m';
assert std.member(container.args, '--dns01-recursive-nameservers-only');
assert std.member(container.args, '--acme-http01-solver-image=quay.io/jetstack/cert-manager-acmesolver:v1.20.0');
assert container.image == 'quay.io/jetstack/cert-manager-controller:v1.20.0';
assert cm.cmValidatingWebhook.webhooks[0].clientConfig.service.namespace == 'certs';
assert cm.cmValidatingWebhook.metadata.annotations['cert-manager.io/inject-ca-from-secret'] == 'certs/cert-manager-webhook-ca';
cm
