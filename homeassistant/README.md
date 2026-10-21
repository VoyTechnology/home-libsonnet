# homeassistant

```jsonnet
local homeassistant = import 'homeassistant/main.libsonnet';

homeassistant {
  _config+:: {
    // When using a mounted device, pin to a node
    nodeName: 'node1',
    devices: { zigbee: '/dev/ttyUSB0' },
    // Optional: your configuration.yaml, rendered to a ConfigMap. Mixin loading is injected.
    configuration: {
      default_config: {},
      automation: homeassistant.include('automations.yaml'),
    },
  },
}
+ homeassistant.addMixins({ energy: import 'energy-mixin/mixin.libsonnet' })
+ homeassistant.addAutomation('porch', { alias: 'Porch', triggers: [], actions: [] })
```

Use `_config+::` (not `_config::`) so the defaults are kept.

Config lives flat under `_config` (see [config.libsonnet](config.libsonnet)). No Ingress or
HTTPRoute is created: expose the `homeassistant` Service however you like. The
ServiceMonitor is opt-in (`metricsEnabled`).

## Mixins

`addMixins` takes a map of mixin name -> mixin and merges the resources of every mixin in
it. A mixin is a plain object, so it can be imported from a library or written inline:

```jsonnet
homeassistant.addMixins({
  // Imported, e.g. a repo with your automations and dashboards
  home: import 'ha-data/mixin.libsonnet',

  // Or inline
  porch: {
    homeassistantAutomations+:: {
      porch_light: {
        alias: 'Porch light at sunset',
        triggers: [{ trigger: 'sun', event: 'sunset' }],
        actions: [{ action: 'light.turn_on', target: { entity_id: 'light.porch' } }],
      },
    },
    homeassistantDashboards+:: {
      porch_overview: { title: 'Porch', icon:: 'mdi:door', views: [{ title: 'Overview', cards: [] }] },
    },
  },
})
```

The names (`home`, `porch`) only label the mixins; resources with the same name are merged
across them. A mixin is an object with any of these fields (name -> resource), see
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

`just test` runs `rustanka show` (set `RTK=tk` to use Tanka) over each Tanka environment in
[test/environments](test/environments): default config, a full mixin set with a managed
`configuration`, sharding against a tiny size limit, and the opt-in ServiceMonitor. Assertions live in each `main.jsonnet`.
