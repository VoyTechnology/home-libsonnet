local ha = (import 'main.libsonnet')
             + { _config+:: { domain: 'ha.example.com', nodeName: 'node1' } }
             + ((import 'main.libsonnet').addMixins({ example: import '../example/mixin.libsonnet' }))
             + ((import 'main.libsonnet').addAutomation('direct', { alias: 'x' }));

local cms = ha.haMixinConfigMaps;
assert std.objectFields(cms) == ['automations', 'dashboards', 'scenes', 'scripts'];
assert std.objectFields(cms.automations.data) == ['direct.yaml', 'porch_light.yaml'];
assert std.objectFields(cms.dashboards.data) == ['energy-overview.yaml', 'registry.yaml'];
assert std.length(ha.haStatefulSet.spec.template.spec.volumes) == 4;
assert std.length(ha.haContainer.volumeMounts) == 5;
assert ha.haStatefulSet.spec.template.spec.nodeSelector['kubernetes.io/hostname'] == 'node1';
// Hidden `icon::` lands in the registry, not in the dashboard itself.
assert std.length(std.findSubstr('mdi:flash', cms.dashboards.data['registry.yaml'])) == 1;
assert std.length(std.findSubstr('icon', cms.dashboards.data['energy-overview.yaml'])) == 0;
ha
