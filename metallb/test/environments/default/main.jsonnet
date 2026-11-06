// Renders with the default config.
local mlb = import '../../../main.libsonnet';

// Every Kubernetes object, whether a top-level field or grouped in a map of them.
local objects(o) =
  if std.objectHas(o, 'kind') then [o]
  else std.flattenArrays([objects(o[f]) for f in std.objectFields(o)]);
local all = objects({ [f]: mlb[f] for f in std.objectFields(mlb) if f != '_config' });
local kinds = std.set([o.kind for o in all]);

assert std.length(std.objectFields(mlb.metallbCrds)) == 8;
assert std.length(all) == 25 : std.length(all);
assert kinds == ['ClusterRole', 'ClusterRoleBinding', 'ConfigMap', 'CustomResourceDefinition', 'DaemonSet', 'Deployment', 'Role', 'RoleBinding', 'Secret', 'Service', 'ServiceAccount', 'ValidatingWebhookConfiguration'] : kinds;
assert mlb.metallbNamespace == {};
assert mlb.metallbWebhookService.spec.selector == mlb.metallbControllerDeployment.spec.selector.matchLabels;
assert mlb.metallbControllerDeployment.spec.template.spec.containers[0].image == 'quay.io/metallb/controller:v0.15.2';
assert std.length(mlb.metallbSpeakerDaemonSet.spec.template.spec.containers) == 4;
assert mlb.metallbControllerClusterRoleBinding.subjects[0].namespace == 'metallb-system';
assert mlb.metallbWebhook.webhooks[0].clientConfig.service.namespace == 'metallb-system';
mlb
