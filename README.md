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
| [`envoy-gateway`](envoy-gateway) | Envoy Gateway control plane (Deployment, Service, RBAC, webhook, Envoy CRDs) |
| [`cloudflare-gateway-controller`](cloudflare-gateway-controller) | cloudflare-gateway-controller, Gateway API over Cloudflare tunnels (Deployment, RBAC, vendored CRDs) |
| [`garage`](garage) | Garage S3-compatible object store (single-replica StatefulSet, Service, bootstrap Job) |
| [`minecraft`](minecraft) | Minecraft server StatefulSet, Services per port and an mc-backup sidecar, configured by mixins |
| [`paperless`](paperless) | Paperless-ngx Deployment with a Redis sidecar and Service, configured by mixins |
| [`donetick`](donetick) | Donetick Deployment on SQLite with ConfigMap, PVC and Service, configured by mixins |
| [`siloserver`](siloserver) | Silo media server (omnibus image) StatefulSet and Service, configured by mixins |
| [`homeassistant`](homeassistant) | Home Assistant StatefulSet/Service/Ingress, plus mixin-provisioned dashboards, automations, scripts and scenes |

Every library keeps its images in `images.libsonnet` as `_images+::` (one `// renovate:` comment per
image). Consumers override them with `_images+::` in their own `images.libsonnet`, which is what
Renovate bumps there. Config knobs stay in `config.libsonnet`.

```sh
mise install
just test    # renders every library as Tanka environments with rustanka
```

## Kubernetes objects

Built-in Kubernetes objects are built with [`k8s-libsonnet`](https://github.com/jsonnet-libs/k8s-libsonnet)
(`local k = import 'k.libsonnet'`) rather than written out by hand. Each library declares the dependency in
its `jsonnetfile.json` (pinned to a commit, Kubernetes 1.35) and ships a `lib/k.libsonnet` that the sample
environments use. That file is the Tanka convention: when you use a library, supply your own `lib/k.libsonnet`
(for instance the same `import 'github.com/jsonnet-libs/k8s-libsonnet/<version>/main.libsonnet'`) to choose
the Kubernetes version. Objects the library does not cover, such as the CRDs of other operators, are still
written by hand.

Selectors are immutable, so `deployment.new` and friends are followed by an explicit `withMatchLabels` and
`template.metadata.withLabels`: the constructors would otherwise add a `name` label. The container mixin
fields (`*_container`) stay plain objects, because consumers extend them with `+:`.

## Naming

New libraries name everything they add to the top level in `snake_case`: the rendered resources
(`silo_statefulset`, `silo_service`) and the hidden fields (`silo_env`, `silo_container`). Prefix them with
the library or component, which keeps the names unique when an app merges several libraries. A consumer's
own resources follow the same rule (`silo_route`, not `siloRoute`).

Kubernetes kinds are one word, however they are capitalised: `silo_statefulset`, not `silo_stateful_set`
(likewise `daemonset`, `configmap`, `httproute`, `externalsecret`).

Libraries that predate this rule keep their names; they are renamed only when they are changed anyway.

## Releases

Each library is versioned on its own with semver, tagged `<library>/vX.Y.Z` (for example
`paperless/v1.4.0`). Consumers can follow `main` or pin a tag in `jsonnetfile.json`:

```sh
jb install github.com/VoyTechnology/home-libsonnet/paperless@paperless/v1.4.0
```

Releases are automatic. Renovate merges minor, patch and digest image bumps once `just test` passes
(majors stay manual PRs). On every push to `main`, [`.github/scripts/release.sh`](.github/scripts/release.sh) tags each
library that changed since its last tag, choosing the bump from conventional commits touching its
directory: `type!:` or `BREAKING CHANGE` is major, `feat` is minor, anything else (including image bumps)
is patch. Before 1.0.0 breaking changes bump the minor and everything else the patch. Run
`.github/scripts/release.sh` without arguments to preview.

## Previewing changes

Every PR gets a comment (updated in place) showing how each library's sample Tanka environments
(`*/test/environments/*`) render differently from `main`. Run it locally with
`RTK="$(mise which rustanka)" .github/scripts/diff.sh [base-ref]`.
