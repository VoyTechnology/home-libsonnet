// Renders the mixin resources (mixins.libsonnet) as ConfigMaps and mounts them under
// `_config.homeassistant.mixinPath/<kind>` in the Home Assistant pod, so they are
// provisioned by Kubernetes rather than synced into /config.
//
// Wire them in from configuration.yaml (labelled keys let them live beside
// UI-managed config):
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

local configMap(kind, data) = {
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: { name: 'ha-mixin-' + kind, labels: { 'app.kubernetes.io/name': 'homeassistant' } },
  data: data,
};

{
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
    local dashboards = $.homeassistantDashboards,
    dashboards: if std.length(dashboards) == 0 then {} else {
      [dashboardID(n) + '.yaml']: yaml(dashboards[n])
      for n in std.objectFields(dashboards)
    } + {
      'registry.yaml': yaml({
        [dashboardID(n)]: {
          mode: 'yaml',
          title: std.get(dashboards[n], 'title', n, true),
          icon: std.get(dashboards[n], 'icon', 'mdi:view-dashboard', true),
          show_in_sidebar: true,
          filename: '%s/dashboards/%s.yaml' % [$._config.homeassistant.mixinPath, dashboardID(n)],
        }
        for n in std.objectFields(dashboards)
      }),
    },
  },
  local kindsInUse = [k for k in std.objectFields(files) if std.length(files[k]) > 0],

  haMixinConfigMaps: {
    [k]: configMap(k, files[k])
    for k in kindsInUse
  },

  // Consumed by the StatefulSet in homeassistant.libsonnet.
  haMixinVolumes:: [
    { name: 'mixin-' + k, configMap: { name: 'ha-mixin-' + k } }
    for k in kindsInUse
  ],
  haMixinMounts:: [
    { name: 'mixin-' + k, mountPath: '%s/%s' % [$._config.homeassistant.mixinPath, k], readOnly: true }
    for k in kindsInUse
  ],
}
