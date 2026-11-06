// Overrides: another namespace and image, no CRDs, extra args.
local op = (import '../../../main.libsonnet') {
  _config+:: { namespace: 'pocketid', createNamespace: true, installCRDs: false, nodeSelector: { role: 'infra' } },
  _images+:: { operator: 'ghcr.io/aclerici38/pocket-id-operator:v0.17.0' },
  manager_container+:: { args+: ['--zap-log-level=debug'] },
};

local container = op.pidDeployment.spec.template.spec.containers[0];
assert op.pidCrds == {};
assert op.pidNamespace.metadata.name == 'pocketid';
assert op.pidDeployment.metadata.namespace == 'pocketid';
assert op.pidDeployment.spec.template.spec.nodeSelector == { role: 'infra' };
assert std.member(container.args, '--zap-log-level=debug');
assert container.image == 'ghcr.io/aclerici38/pocket-id-operator:v0.17.0';
assert op.pidLeaderElectionRoleBinding.subjects[0].namespace == 'pocketid';
op
