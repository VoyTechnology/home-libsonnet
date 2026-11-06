// Renders with the default config.
local eg = import '../../../main.libsonnet';

// Every Kubernetes object, whether a top-level field or grouped in a map of them.
local objects(o) =
  if std.objectHas(o, 'kind') then [o]
  else std.flattenArrays([objects(o[f]) for f in std.objectFields(o)]);
local all = objects({ [f]: eg[f] for f in std.objectFields(eg) if f != '_config' });

assert std.length(std.objectFields(eg.envoyGatewayCrds)) == 8;
assert std.length(all) == 25 : std.length(all);
assert eg.envoyGatewayNamespace == {};
assert eg.envoyGatewayService.spec.selector == {
  'control-plane': 'envoy-gateway',
  'app.kubernetes.io/name': 'gateway-helm',
  'app.kubernetes.io/instance': 'envoy',
};
assert std.length(eg.envoyGatewayCertgen) == 6;
assert eg.envoyGatewayClusterRoleBinding.subjects[0].namespace == 'envoy-gateway-system';
assert eg.envoyGatewayCertgen.clusterRole.metadata.name == 'envoy-gateway-helm-certgen:envoy-gateway-system';
eg
