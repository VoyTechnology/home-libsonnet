// Overrides: another namespace, a bucket, a storage class and a container mixin.
local g = (import '../../../main.libsonnet') {
  _config+:: {
    namespace: 'metrics-system',
    buckets: ['mimir'],
    storageClassName: 'longhorn',
  },
  garage_container+:: { args+: ['server'] },
};

local sts = g.garageStatefulSet;
local container = sts.spec.template.spec.containers[0];
assert sts.metadata.namespace == 'metrics-system';
assert sts.spec.volumeClaimTemplates[1].spec.storageClassName == 'longhorn';
assert container.args == ['server'];
assert g.garageService.spec.selector == sts.spec.selector.matchLabels;
assert g.garageNamespace == {};
assert std.length(std.findSubstr('for bucket in mimir;', g.garageBootstrapJob.spec.template.spec.containers[0].command[2])) == 1;
g
