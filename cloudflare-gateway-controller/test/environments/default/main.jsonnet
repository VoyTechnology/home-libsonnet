// Renders with the default config (only the required cluster name set).
local c = (import '../../../main.libsonnet') { _config+:: { clusterName: 'test' } };

// Every Kubernetes object, whether a top-level field or grouped in a map of them.
local objects(o) =
  if std.objectHas(o, 'kind') then [o]
  else std.flattenArrays([objects(o[f]) for f in std.objectFields(o)]);
local all = objects({ [f]: c[f] for f in std.objectFields(c) if f != '_config' });
local kinds = std.set([o.kind for o in all]);

// The vendored CRDs must come from the version being deployed.
local tag(image) = std.reverse(std.split(std.split(image, '@')[0], ':'))[0];
local container = c.cgcDeployment.spec.template.spec.containers[0];
assert tag(c._images.controller) == importstr '../../../crds/VERSION' : 'run generate.sh and set images.libsonnet to match crds/VERSION';
assert std.length(std.objectFields(c.cgcCrds)) == 2;
assert std.length(all) == 8 : std.length(all);
assert kinds == ['ClusterRole', 'ClusterRoleBinding', 'CustomResourceDefinition', 'Deployment', 'Role', 'RoleBinding', 'ServiceAccount'] : kinds;
assert c.cgcNamespace == {};
assert container.args == ['controller', '--cluster-name=test', '--tunnel-image=' + c._images.controller];
assert std.all([o.metadata.namespace == 'cloudflare-gateway-system' for o in all if std.member(['Deployment', 'ServiceAccount', 'Role', 'RoleBinding'], o.kind)]);
assert c.cgcClusterRoleBinding.subjects[0].namespace == 'cloudflare-gateway-system';
c
