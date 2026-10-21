# homeassistant

```jsonnet
local ha = import 'homeassistant/main.libsonnet';

ha
+ {
  _config+:: {
    nodeName: 'node1',
    devices: { zigbee: '/dev/ttyUSB0' },
    // Optional: your configuration.yaml, rendered to a ConfigMap. Mixin loading is injected.
    configuration: {
      default_config: {},
      automation: ha.include('automations.yaml'),
    },
  },
}
+ ha.addMixins({ energy: import 'energy-mixin/mixin.libsonnet' })
+ ha.addAutomation('porch', { alias: 'Porch', triggers: [], actions: [] })
```

Config lives flat under `_config` (see [config.libsonnet](config.libsonnet)). No Ingress or
HTTPRoute is created: expose the `homeassistant` Service however you like. The
ServiceMonitor is opt-in (`metricsEnabled`).

## Mixins

A mixin is an object with any of these fields (name -> resource), see
[example/mixin.libsonnet](example/mixin.libsonnet):

- `homeassistantDashboards`: Lovelace config. Hidden `icon::` sets the sidebar icon, `title` the title. Names need a `-` or `_`.
- `homeassistantAutomations`: an automation or a list of them.
- `homeassistantScripts`: a script.
- `homeassistantScenes`: a scene or a list of them.

Each kind becomes a ConfigMap (`ha-mixin-<kind>`) mounted read-only at
`/config/mixins/<kind>`, so no sync is needed.

With `_config.configuration` set, the library renders it to `/config/configuration.yaml`
(restarting the pod when it changes) and adds the sections that load the mixins, merging
dashboards into your `lovelace.dashboards`. Use `ha.include(path)` and
`ha.includeDir('merge_list', path)` for `!include` tags. With it unset, `configuration.yaml`
is untouched and you add the includes yourself:

```yaml
automation managed: !include_dir_merge_list mixins/automations
script managed: !include_dir_merge_named mixins/scripts
scene managed: !include_dir_merge_list mixins/scenes
lovelace:
  dashboards: !include mixins/dashboards/registry.yaml
```

ConfigMaps are limited to 1MiB each, and HA must be reloaded to pick up changes.
