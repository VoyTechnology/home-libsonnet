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

// Everything fits in one shard, mounted through a single projected volume.
local cms = ha.haMixinConfigMaps;
local data = cms['ha-mixins-0'].data;
assert std.objectFields(cms) == ['ha-mixins-0'] : std.objectFields(cms);
assert std.objectFields(data) == [
  'automations.direct.yaml',
  'automations.porch_light.yaml',
  'configuration.yaml',
  'dashboards.energy-overview.yaml',
  'dashboards.registry.yaml',
  'scenes.movie.yaml',
  'scripts.goodnight.yaml',
] : std.objectFields(data);
assert std.length(ha.haStatefulSet.spec.template.spec.volumes) == 1;
assert std.length(ha.haContainer.volumeMounts) == 3;
assert ha.haStatefulSet.spec.template.spec.nodeSelector['kubernetes.io/hostname'] == 'node1';
assert std.objectHas(ha.haStatefulSet.spec.template.metadata.annotations, 'checksum/configuration');
// Hidden `icon::` lands in the registry, not in the dashboard itself.
assert std.length(std.findSubstr('mdi:flash', data['dashboards.registry.yaml'])) == 1;
assert std.length(std.findSubstr('icon', data['dashboards.energy-overview.yaml'])) == 0;

// The user's configuration is kept, the mixin sections are injected, tags are unquoted.
local conf = ha.haConfiguration;
local has(s) = std.length(std.findSubstr(s, conf)) > 0;
assert has('default_config:');
assert has('automation: !include automations.yaml');
assert has('"automation managed": !include_dir_merge_list /config/mixins/automations');
assert has('"script managed": !include_dir_merge_named /config/mixins/scripts');
assert has('my-board');
assert has('energy-overview:');
ha
