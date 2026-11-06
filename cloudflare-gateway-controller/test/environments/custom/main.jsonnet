// Overrides: another namespace and image, no CRDs, extra args.
local c = (import '../../../main.libsonnet') {
  _config+:: { clusterName: 'test', namespace: 'gw', createNamespace: true, installCRDs: false, nodeSelector: { role: 'infra' } },
  _images+:: { controller: 'ghcr.io/matheuscscp/cloudflare-gateway-controller:v0.17.0' },
  controller_container+:: { args+: ['--zap-log-level=debug'] },
};

local container = c.cgcDeployment.spec.template.spec.containers[0];
assert c.cgcCrds == {};
assert c.cgcNamespace.metadata.name == 'gw';
assert c.cgcDeployment.metadata.namespace == 'gw';
assert c.cgcDeployment.spec.template.spec.nodeSelector == { role: 'infra' };
assert std.member(container.args, '--zap-log-level=debug');
assert std.member(container.args, '--tunnel-image=ghcr.io/matheuscscp/cloudflare-gateway-controller:v0.17.0');
assert c.cgcLeaderElectionRoleBinding.subjects[0].namespace == 'gw';
c
