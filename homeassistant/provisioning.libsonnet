// Renders the mixin resources (mixins.libsonnet) as ConfigMaps and mounts them under
// `_config.mixinPath/<kind>` in the Home Assistant pod, so they are provisioned by
// Kubernetes rather than synced into /config.
//
// Files of all kinds are bin-packed (first-fit decreasing) into as few ConfigMaps as
// fit under `_config.mixinShardBytes`, and a single projected volume stitches the
// shards back into one directory tree.
//
// With `_config.configuration` set, the include sections are injected into the
// rendered configuration.yaml. Otherwise add them by hand:
//
//   automation managed: !include_dir_merge_list mixins/automations
//   script managed: !include_dir_merge_named mixins/scripts
//   scene managed: !include_dir_merge_list mixins/scenes
//   lovelace:
//     dashboards: !include mixins/dashboards/registry.yaml
//
// Contents update in place; reload the domain (or restart HA) to apply.
local yaml(v) = std.manifestYamlDoc(v, quote_keys=false);
local asList(v) = if std.isArray(v) then v else [v];

// Dashboard URL paths must contain a hyphen.
local dashboardID(name) =
  local id = std.strReplace(name, '_', '-');
  assert std.length(std.findSubstr('-', id)) > 0 :
         'dashboard "%s" needs a hyphen or underscore in its name (HA url_path rule)' % name;
  id;

local byteSize(s) = std.length(std.encodeUTF8(s));

local configMap(name, data) = {
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: { name: name, labels: { 'app.kubernetes.io/name': 'homeassistant' } },
  data: data,
};

{
  local dashboards = $.homeassistantDashboards,
  local dashboardRegistry = {
    [dashboardID(n)]: {
      mode: 'yaml',
      title: std.get(dashboards[n], 'title', n, true),
      icon: std.get(dashboards[n], 'icon', 'mdi:view-dashboard', true),
      show_in_sidebar: true,
      filename: '%s/dashboards/%s.yaml' % [$._config.mixinPath, dashboardID(n)],
    }
    for n in std.objectFields(dashboards)
  },

  // kind -> { file: content }; empty kinds are omitted.
  local files = {
    automations: {
      [n + '.yaml']: yaml(asList($.homeassistantAutomations[n]))
      for n in std.objectFields($.homeassistantAutomations)
    },
    scripts: {
      [n + '.yaml']: yaml({ [n]: $.homeassistantScripts[n] })
      for n in std.objectFields($.homeassistantScripts)
    },
    scenes: {
      [n + '.yaml']: yaml(asList($.homeassistantScenes[n]))
      for n in std.objectFields($.homeassistantScenes)
    },
    dashboards: if std.length(dashboards) == 0 then {} else {
      [dashboardID(n) + '.yaml']: yaml(dashboards[n])
      for n in std.objectFields(dashboards)
    } + { 'registry.yaml': yaml(dashboardRegistry) },
  },
  local kindsInUse = [k for k in std.objectFields(files) if std.length(files[k]) > 0],

  local inUse(k) = std.member(kindsInUse, k),
  local path(k) = '%s/%s' % [$._config.mixinPath, k],

  // `!include*` tags can't be expressed in JSON: they are written as strings and
  // unquoted after rendering.
  includeDir(kind, p):: '!include_dir_%s %s' % [kind, p],
  include(p):: '!include ' + p,

  // The injected sections that load the mixins.
  local managed =
    (if inUse('automations') then { 'automation managed': $.includeDir('merge_list', path('automations')) } else {})
    + (if inUse('scripts') then { 'script managed': $.includeDir('merge_named', path('scripts')) } else {})
    + (if inUse('scenes') then { 'scene managed': $.includeDir('merge_list', path('scenes')) } else {})
    + (if inUse('dashboards') then {
         lovelace+: {
           dashboards+:
             (assert !std.isString(std.get(std.get($._config.configuration, 'lovelace', {}), 'dashboards', {})) :
                     'lovelace.dashboards must be an object to merge mixin dashboards into it';
              {}) + dashboardRegistry,
         },
       } else {}),

  local collectIncludes(v) =
    if std.isString(v) then (if std.startsWith(v, '!include') then [v] else [])
    else if std.isObject(v) then std.flattenArrays([collectIncludes(v[f]) for f in std.objectFields(v)])
    else if std.isArray(v) then std.flattenArrays(std.map(collectIncludes, v))
    else [],

  // The rendered configuration.yaml ('' when unmanaged).
  haConfiguration::
    if $._config.configuration == null then '' else
      local full = $._config.configuration + managed;
      std.foldl(
        function(out, tag) std.strReplace(out, '"%s"' % tag, tag),
        std.set(collectIncludes(full)),
        yaml(full)
      ),

  // Everything to provision: ConfigMap key, path inside the volume and content.
  local entries =
    [
      { key: '%s.%s' % [k, f], path: '%s/%s' % [k, f], content: files[k][f] }
      for k in kindsInUse
      for f in std.objectFields(files[k])
    ]
    + (if $._config.configuration == null then [] else [
      { key: 'configuration.yaml', path: 'configuration.yaml', content: $.haConfiguration },
    ]),

  // First-fit decreasing: biggest files first, each into the first shard with room.
  local limit = $._config.mixinShardBytes,
  local sized = [
    e + { size: byteSize(e.key) + byteSize(e.content) }
    for e in entries
  ],
  local shards = std.foldl(
    function(shards, e)
      assert e.size <= limit :
             '%s is %d bytes, over the %d byte ConfigMap limit (_config.mixinShardBytes)' % [e.key, e.size, limit];
      local fits = [i for i in std.range(0, std.length(shards) - 1) if shards[i].size + e.size <= limit];
      if std.length(fits) == 0 then shards + [{ size: e.size, entries: [e] }]
      else
        [
          if i == fits[0] then { size: shards[i].size + e.size, entries: shards[i].entries + [e] } else shards[i]
          for i in std.range(0, std.length(shards) - 1)
        ],
    std.sort(sized, function(e) [-e.size, e.key]),
    []
  ),
  local shardName(i) = 'ha-mixins-%d' % i,

  // ConfigMaps holding the mixins (and configuration.yaml), as few as fit.
  haMixinConfigMaps: {
    [shardName(i)]: configMap(shardName(i), { [e.key]: e.content for e in shards[i].entries })
    for i in std.range(0, std.length(shards) - 1)
  },

  // Consumed by the StatefulSet in homeassistant.libsonnet.
  haProvisioningVolumes:: if std.length(shards) == 0 then [] else [{
    name: 'mixins',
    projected: { sources: [
      { configMap: { name: shardName(i), items: [{ key: e.key, path: e.path } for e in shards[i].entries] } }
      for i in std.range(0, std.length(shards) - 1)
    ] },
  }],
  haProvisioningMounts:: if std.length(shards) == 0 then [] else [
    { name: 'mixins', mountPath: $._config.mixinPath, readOnly: true },
  ] + (if $._config.configuration == null then [] else [
    { name: 'mixins', mountPath: '/config/configuration.yaml', subPath: 'configuration.yaml', readOnly: true },
  ]),
}
