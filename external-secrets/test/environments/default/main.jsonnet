// Renders with the default config.
local es = import '../../../main.libsonnet';

local objects = [
  o
  for f in std.objectFields(es)
  if std.isObject(es[f]) && std.objectHas(es[f], 'kind')
  for o in [es[f]]
];
local kinds = std.set([o.kind for o in objects]);

// The vendored CRDs must come from the version being deployed.
assert es._config.version == importstr '../../../crds/VERSION' : 'run generate-crds.sh for ' + es._config.version;
assert std.length(std.objectFields(es.esCrds)) == 21;
assert kinds == ['ClusterRole', 'ClusterRoleBinding', 'Deployment', 'Role', 'RoleBinding', 'Secret', 'Service', 'ServiceAccount', 'ValidatingWebhookConfiguration'] : kinds;
assert es.esNamespace == {};
// Every namespaced object is in the configured namespace.
assert std.all([o.metadata.namespace == 'external-secrets' for o in objects if std.member(['Deployment', 'Role', 'RoleBinding', 'Secret', 'Service', 'ServiceAccount'], o.kind)]);
es
