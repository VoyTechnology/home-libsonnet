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

  // Merge a mixin (an object with any of the fields above) into this library.
  addMixins(mixin)::
    std.foldl(
      function(acc, kind) acc + (
        if std.objectHasAll(mixin, kind) then { [kind]+:: mixin[kind] } else {}
      ),
      kinds,
      {}
    ),
}
