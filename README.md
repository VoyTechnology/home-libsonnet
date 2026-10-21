# home-libsonnet

Self-contained Jsonnet libraries for my homelab, one folder each (layout modelled on
[grafana/jsonnet-libs](https://github.com/grafana/jsonnet-libs)).

| Library | What |
| --- | --- |
| [`homeassistant`](homeassistant) | Home Assistant StatefulSet/Service/Ingress, plus mixin-provisioned dashboards, automations, scripts and scenes |

```sh
mise install
just test    # renders every library as Tanka environments with rustanka
```
