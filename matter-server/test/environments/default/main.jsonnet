// Overrides: a node, a container mixin, a pod spec mixin and a storage class.
local m = (import '../../../main.libsonnet') {
  _config+:: { networkInterface: 'eth0', nodeName: 'node1', dataStorageClass: 'fast' },
  matter_container+:: { args+: ['--vendorid', '4939'] },
  pod_spec+:: { tolerations: [{ operator: 'Exists' }] },
};

local sts = m.matterStatefulSet;
local pod = sts.spec.template.spec;
local c = pod.containers[0];
assert sts.metadata.name == 'homeassistant-matter';
assert sts.spec.selector.matchLabels == {
  'app.kubernetes.io/instance': 'homeassistant',
  'app.kubernetes.io/name': 'matter',
};
assert sts.spec.volumeClaimTemplates[0].metadata.name == 'data';
assert sts.spec.volumeClaimTemplates[0].spec.storageClassName == 'fast';
assert c.args[std.length(c.args) - 2:] == ['--vendorid', '4939'];
assert std.member(c.args, 'eth0');
assert pod.nodeSelector == { 'kubernetes.io/hostname': 'node1' };
assert pod.serviceAccountName == m.matterServiceAccount.metadata.name;
assert m.matterService.spec.selector == sts.spec.selector.matchLabels;
m
