// Overrides: another namespace and version, no CRDs or network policies, args and sizing.
local cm = (import '../../../main.libsonnet') {
  _config+:: {
    namespace: 'certs',
    createNamespace: true,
    version: 'v1.20.0',
    installCRDs: false,
    webhookNetworkPolicy: false,
    replicas+: { controller: 2 },
    resources: { controller: { requests: { cpu: '10m' } } },
    nodeSelector: { role: 'infra' },
    extraArgs+: { controller: ['--dns01-recursive-nameservers-only'] },
  },
};

local controller = cm.cmObjects['deployment-cert-manager'];
assert cm.cmCrds == {};
assert cm.cmNamespace.metadata.name == 'certs';
assert controller.metadata.namespace == 'certs';
assert controller.spec.replicas == 2;
assert controller.spec.template.spec.nodeSelector == { role: 'infra' };
assert controller.spec.template.spec.containers[0].resources.requests.cpu == '10m';
assert std.member(controller.spec.template.spec.containers[0].args, '--dns01-recursive-nameservers-only');
assert std.endsWith(controller.spec.template.spec.containers[0].image, ':v1.20.0');
assert !std.objectHas(cm.cmObjects, 'networkpolicy-cert-manager-webhook-allow-egress');
cm
