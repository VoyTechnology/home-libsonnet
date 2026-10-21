// Renders the mixin resources (mixins.libsonnet) as ConfigMaps and mounts them under
// `_config.homeassistant.mixinPath/<kind>` in the Home Assistant pod, so they are
// provisioned by Kubernetes rather than synced into /config.
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
// ConfigMap contents update in place; reload the domain (or restart HA) to apply.
local yaml(v) = std.manifestYamlDoc(v, quote_keys=false);
local asList(v) = if std.isArray(v) then v else [v];

// Dashboard URL paths must contain a hyphen.
local dashboardID(name) =
  local id = std.strReplace(name, '_', '-');
  assert std.length(std.findSubstr('-', id)) > 0 :
         'dashboard "%s" needs a hyphen or underscore in its name (HA url_path rule)' % name;
  id;

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

  haMixinConfigMaps: {
    [k]: configMap('ha-mixin-' + k, files[k])
    for k in kindsInUse
  },

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

  haConfigMap: if $._config.configuration == null then {} else
    configMap('ha-configuration', { 'configuration.yaml': $.haConfiguration }),

  // Consumed by the StatefulSet in homeassistant.libsonnet.
  haProvisioningVolumes:: [
    { name: 'mixin-' + k, configMap: { name: 'ha-mixin-' + k } }
    for k in kindsInUse
  ] + (if $._config.configuration == null then [] else [
    { name: 'configuration', configMap: { name: 'ha-configuration' } },
  ]),
  haProvisioningMounts:: [
    { name: 'mixin-' + k, mountPath: path(k), readOnly: true }
    for k in kindsInUse
  ] + (if $._config.configuration == null then [] else [
    { name: 'configuration', mountPath: '/config/configuration.yaml', subPath: 'configuration.yaml', readOnly: true },
  ]),
}
