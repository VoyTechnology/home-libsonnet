// Many automations of varying size against a tiny shard limit.
local main = import '../../../main.libsonnet';
local limit = 4000;

local automation(i) = {
  alias: 'automation %d' % i,
  actions: [{ action: 'light.turn_on', data: { note: std.join('', ['x' for _ in std.range(0, (i * 37) % 600)]) } }],
};
local names = ['auto_%02d' % i for i in std.range(0, 29)];

local ha = main
           + { _config+:: { mixinShardBytes: limit } }
           + main.addMixins({ big: { homeassistantAutomations+:: { [n]: automation(i) for i in std.range(0, 29) for n in [names[i]] } } });

local cms = ha.haMixinConfigMaps;
local size(cm) = std.foldl(function(a, k) a + std.length(std.encodeUTF8(k)) + std.length(std.encodeUTF8(cm.data[k])), std.objectFields(cm.data), 0);
local keys = std.flattenArrays([std.objectFields(cms[c].data) for c in std.objectFields(cms)]);
local total = std.foldl(function(a, c) a + size(cms[c]), std.objectFields(cms), 0);

assert std.length(cms) > 1 : 'expected several shards';
// Every shard is within the limit.
assert std.all([size(cms[c]) <= limit for c in std.objectFields(cms)]);
// Every file is in exactly one shard.
assert std.length(keys) == 30 && std.length(std.set(keys)) == 30;
// Well packed: no more shards than the ideal lower bound plus a little slack.
assert std.length(cms) <= std.ceil(total / limit) + 1 : [std.length(cms), total];
// The projected volume references every shard and every file.
local sources = ha.haProvisioningVolumes[0].projected.sources;
assert std.length(sources) == std.length(cms);
assert std.length(std.flattenArrays([s.configMap.items for s in sources])) == 30;
ha
