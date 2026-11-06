// Renders with the default config.
local cm = import '../../../main.libsonnet';

local objects = [o for k in std.objectFields(cm.cmObjects) for o in [cm.cmObjects[k]]];
local kinds = std.set([o.kind for o in objects]);

// The vendored CRDs must come from the version being deployed.
assert cm._config.version == importstr '../../../crds/VERSION' : 'run generate.sh for ' + cm._config.version;
assert std.length(std.objectFields(cm.cmCrds)) == 6;
assert kinds == ['ClusterRole', 'ClusterRoleBinding', 'Deployment', 'MutatingWebhookConfiguration', 'NetworkPolicy', 'Role', 'RoleBinding', 'Service', 'ServiceAccount', 'ValidatingWebhookConfiguration'] : kinds;
assert cm.cmNamespace == {};
// No placeholder is left behind and namespaced objects are in the configured namespace.
assert !std.member(std.manifestJsonMinified(objects), '__NAMESPACE__');
assert cm.cmObjects['deployment-cert-manager'].metadata.namespace == 'cert-manager';
assert cm.cmObjects['clusterrolebinding-cert-manager-webhook-subjectaccessreviews'].subjects[0].namespace == 'cert-manager';
cm
