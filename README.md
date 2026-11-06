# home-libsonnet

Self-contained Jsonnet libraries for my homelab, one folder each (layout modelled on
[grafana/jsonnet-libs](https://github.com/grafana/jsonnet-libs)).

| Library | What |
| --- | --- |
| [`external-secrets`](external-secrets) | External Secrets Operator (Deployments, RBAC, webhook, vendored CRDs) |
| [`external-dns`](external-dns) | external-dns (Deployment, RBAC, Service, vendored CRDs) |
| [`cert-manager`](cert-manager) | cert-manager (Deployments, RBAC, webhooks, NetworkPolicies, vendored CRDs) |
| [`pocket-id-operator`](pocket-id-operator) | pocket-id-operator (Deployment, RBAC, Service, vendored CRDs) |
| [`metallb`](metallb) | MetalLB (controller, speaker with FRR, RBAC, webhook, vendored CRDs) |
| [`cloudflare-gateway-controller`](cloudflare-gateway-controller) | cloudflare-gateway-controller, Gateway API over Cloudflare tunnels (Deployment, RBAC, vendored CRDs) |
| [`homeassistant`](homeassistant) | Home Assistant StatefulSet/Service/Ingress, plus mixin-provisioned dashboards, automations, scripts and scenes |

Every library keeps its images in `images.libsonnet` as `_images+::` (one `// renovate:` comment per
image). Consumers override them with `_images+::` in their own `images.libsonnet`, which is what
Renovate bumps there. Config knobs stay in `config.libsonnet`.

```sh
mise install
just test    # renders every library as Tanka environments with rustanka
```
