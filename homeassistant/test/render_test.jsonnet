// Renders with the default config.
local ha = import 'main.libsonnet';

local kinds = std.set([ha[f].kind for f in std.objectFields(ha) if std.isObject(ha[f]) && std.objectHas(ha[f], 'kind')]);

assert kinds == ['Service', 'ServiceAccount', 'StatefulSet'] : kinds;
// No mixins and no managed configuration: nothing is provisioned or mounted.
assert ha.haMixinConfigMaps == {};
assert ha.haConfigMap == {};
assert std.length(ha.haStatefulSet.spec.template.spec.volumes) == 0;
assert !std.objectHas(ha.haStatefulSet.spec.template.spec, 'nodeSelector');
assert !std.objectHas(ha.haStatefulSet.spec.template.metadata, 'annotations');
ha
