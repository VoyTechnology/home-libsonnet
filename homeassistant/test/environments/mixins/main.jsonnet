local main = import '../../../main.libsonnet';
local ha = main
             + { _config+:: {
               nodeName: 'node1',
               configuration: {
                 default_config: {},
                 automation: main.include('automations.yaml'),
                 lovelace: { mode: 'storage', dashboards: { 'my-board': { mode: 'storage', title: 'Mine' } } },
               },
             } }
             + main.addMixins({ example: import '../../../example/mixin.libsonnet' })
             + main.addAutomation('direct', { alias: 'x' });

local cms = ha.haMixinConfigMaps;
assert std.objectFields(cms) == ['automations', 'dashboards', 'scenes', 'scripts'];
assert std.objectFields(cms.automations.data) == ['direct.yaml', 'porch_light.yaml'];
assert std.objectFields(cms.dashboards.data) == ['energy-overview.yaml', 'registry.yaml'];
assert std.length(ha.haStatefulSet.spec.template.spec.volumes) == 5;
assert std.length(ha.haContainer.volumeMounts) == 6;
assert ha.haStatefulSet.spec.template.spec.nodeSelector['kubernetes.io/hostname'] == 'node1';
assert std.objectHas(ha.haStatefulSet.spec.template.metadata.annotations, 'checksum/configuration');
// Hidden `icon::` lands in the registry, not in the dashboard itself.
assert std.length(std.findSubstr('mdi:flash', cms.dashboards.data['registry.yaml'])) == 1;
assert std.length(std.findSubstr('icon', cms.dashboards.data['energy-overview.yaml'])) == 0;

// The user's configuration is kept, the mixin sections are injected, tags are unquoted.
local conf = ha.haConfigMap.data['configuration.yaml'];
local has(s) = std.length(std.findSubstr(s, conf)) > 0;
assert has('default_config:');
assert has('automation: !include automations.yaml');
assert has('"automation managed": !include_dir_merge_list /config/mixins/automations');
assert has('"script managed": !include_dir_merge_named /config/mixins/scripts');
assert has('my-board');
assert has('energy-overview:');
ha
