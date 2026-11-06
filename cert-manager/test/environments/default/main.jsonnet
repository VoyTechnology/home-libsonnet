// Renders with the default config.
local cm = import '../../../main.libsonnet';

// Every Kubernetes object, whether a top-level field or grouped in a map of them.
local objects(o) =
  if std.objectHas(o, 'kind') then [o]
  else std.flattenArrays([objects(o[f]) for f in std.objectFields(o)]);
local all = objects({ [f]: cm[f] for f in std.objectFields(cm) if f != '_config' });
local kinds = std.set([o.kind for o in all]);

// The vendored CRDs must come from the version being deployed.
local tag(image) = std.reverse(std.split(image, ':'))[0];
assert std.all([tag(cm._images[i]) == importstr '../../../crds/VERSION' for i in std.objectFields(cm._images)]) : 'run generate.sh and set images.libsonnet to match crds/VERSION';
assert std.length(std.objectFields(cm.cmCrds)) == 6;
assert std.length(all) == 50 : std.length(all);
assert kinds == ['ClusterRole', 'ClusterRoleBinding', 'CustomResourceDefinition', 'Deployment', 'MutatingWebhookConfiguration', 'NetworkPolicy', 'Role', 'RoleBinding', 'Service', 'ServiceAccount', 'ValidatingWebhookConfiguration'] : kinds;
assert cm.cmNamespace == {};
// Namespaced objects are in the configured namespace and the version is applied everywhere.
assert std.all([o.metadata.namespace == 'cert-manager' for o in all if std.member(['Deployment', 'Service', 'ServiceAccount', 'NetworkPolicy'], o.kind)]);
assert cm.cmControllerDeployment.spec.template.spec.containers[0].image == 'quay.io/jetstack/cert-manager-controller:v1.19.1';
assert cm.cmWebhookService.spec.selector == cm.cmWebhookDeployment.spec.selector.matchLabels;
assert cm.cmControllerClusterRoleBindings['cert-manager-controller-issuers'].subjects[0].namespace == 'cert-manager';
cm
