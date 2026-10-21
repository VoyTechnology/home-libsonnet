// Renders with the minimal config (only `domain` is required).
local ha = (import 'main.libsonnet') + { _config+:: { domain: 'ha.example.com' } };

local kinds = std.set([ha[f].kind for f in std.objectFields(ha) if std.isObject(ha[f]) && std.objectHas(ha[f], 'kind')]);

assert kinds == ['Ingress', 'Service', 'ServiceAccount', 'ServiceMonitor', 'StatefulSet'] : kinds;
// No mixins, so nothing is provisioned and nothing extra is mounted.
assert ha.haMixinConfigMaps == {};
assert std.length(ha.haStatefulSet.spec.template.spec.volumes) == 0;
assert !std.objectHas(ha.haStatefulSet.spec.template.spec, 'nodeSelector');
ha
