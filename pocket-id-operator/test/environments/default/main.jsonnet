// Renders with the default config.
local op = import '../../../main.libsonnet';

// Every Kubernetes object, whether a top-level field or grouped in a map of them.
local objects(o) =
  if std.objectHas(o, 'kind') then [o]
  else std.flattenArrays([objects(o[f]) for f in std.objectFields(o)]);
local all = objects({ [f]: op[f] for f in std.objectFields(op) if f != '_config' });
local kinds = std.set([o.kind for o in all]);

// The vendored CRDs must come from the version being deployed.
local tag(image) = std.reverse(std.split(std.split(image, '@')[0], ':'))[0];
assert tag(op._images.operator) == importstr '../../../crds/VERSION' : 'run generate.sh and set images.libsonnet to match crds/VERSION';
assert std.length(std.objectFields(op.pidCrds)) == 5;
assert std.length(all) == 12 : std.length(all);
assert kinds == ['ClusterRole', 'ClusterRoleBinding', 'CustomResourceDefinition', 'Deployment', 'Role', 'RoleBinding', 'Service', 'ServiceAccount'] : kinds;
assert op.pidNamespace == {};
assert std.all([o.metadata.namespace == 'pocket-id-operator-system' for o in all if std.member(['Deployment', 'Service', 'ServiceAccount', 'Role', 'RoleBinding'], o.kind)]);
assert op.pidMetricsService.spec.selector == op.pidDeployment.spec.selector.matchLabels;
assert op.pidManagerClusterRoleBinding.subjects[0].namespace == 'pocket-id-operator-system';
op
