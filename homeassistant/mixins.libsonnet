// Mixin plumbing, modelled on grafana/jsonnet-libs' dashboards.libsonnet.
//
// A mixin is any object exposing some of these (hidden or visible) fields, each a
// map of name -> resource:
//
//   homeassistantDashboards  name -> Lovelace config (hidden `icon::` sets the sidebar icon)
//   homeassistantAutomations name -> automation, or list of automations
//   homeassistantScripts     name -> script
//   homeassistantScenes      name -> scene, or list of scenes
//
// They are rendered into ConfigMaps by provisioning.libsonnet.
local kinds = [
  'homeassistantDashboards',
  'homeassistantAutomations',
  'homeassistantScripts',
  'homeassistantScenes',
];

{
  homeassistantDashboards+:: {},
  homeassistantAutomations+:: {},
  homeassistantScripts+:: {},
  homeassistantScenes+:: {},

  addDashboard(name, dashboard):: { homeassistantDashboards+:: { [name]+: dashboard } },
  addAutomation(name, automation):: { homeassistantAutomations+:: { [name]: automation } },
  addScript(name, script):: { homeassistantScripts+:: { [name]+: script } },
  addScene(name, scene):: { homeassistantScenes+:: { [name]: scene } },

  // Merge the resources of every mixin in `mixins` (name -> mixin) into this library.
  addMixins(mixins)::
    std.foldl(
      function(acc, kind) acc + {
        [kind]+:: std.foldl(
          function(m, name)
            m + (if std.objectHasAll(mixins[name], kind) then mixins[name][kind] else {}),
          std.objectFields(mixins),
          {}
        ),
      },
      kinds,
      {}
    ),
}
