# homeassistant

```jsonnet
local ha = import 'homeassistant/main.libsonnet';

ha
+ { _config+:: { domain: 'ha.example.com', nodeName: 'node1', devices: { zigbee: '/dev/ttyUSB0' } } }
+ ha.addMixins({ energy: import 'energy-mixin/mixin.libsonnet' })
+ ha.addAutomation('porch', { alias: 'Porch', triggers: [], actions: [] })
```

## Mixins

A mixin is an object with any of these fields (name -> resource), see
[example/mixin.libsonnet](example/mixin.libsonnet):

- `homeassistantDashboards`: Lovelace config. Hidden `icon::` sets the sidebar icon, `title` the title. Names need a `-` or `_`.
- `homeassistantAutomations`: an automation or a list of them.
- `homeassistantScripts`: a script.
- `homeassistantScenes`: a scene or a list of them.

Each kind becomes a ConfigMap (`ha-mixin-<kind>`) mounted read-only at
`/config/mixins/<kind>`, so no sync is needed. Reference them from `configuration.yaml`:

```yaml
automation managed: !include_dir_merge_list mixins/automations
script managed: !include_dir_merge_named mixins/scripts
scene managed: !include_dir_merge_list mixins/scenes
lovelace:
  dashboards: !include mixins/dashboards/registry.yaml
```

ConfigMaps are limited to 1MiB each, and HA must be reloaded to pick up changes.
