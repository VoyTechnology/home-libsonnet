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

All files (and the managed `configuration.yaml`) are bin-packed into as few ConfigMaps
(`ha-mixins-<n>`) as fit under `_config.mixinShardBytes` (default 900KiB, Kubernetes allows
1MiB), and one projected volume mounts them read-only at `/config/mixins/<kind>/`, so no sync
is needed (the managed `configuration.yaml` also shows up at `/config/mixins/configuration.yaml`, the real one is a subPath mount). A single file larger than the limit fails the render.

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

Contents update in place when they change; HA must be reloaded to pick them up. Which shard a file lands in can change as content grows.

## Tests

`make test` runs `rustanka show` (set `RTK=tk` to use Tanka) over each Tanka environment in
[test/environments](test/environments): default config, a full mixin set with a managed
`configuration`, sharding against a tiny size limit, and the opt-in ServiceMonitor. Assertions live in each `main.jsonnet`.
