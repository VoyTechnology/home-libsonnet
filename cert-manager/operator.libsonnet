// cert-manager, taken from the upstream Helm chart's default rendering (see
// generate.sh): controller, webhook and cainjector Deployments with their RBAC,
// Services, webhook configurations and NetworkPolicies, plus the vendored CRDs.
// The rendered objects are patched by `_config`; names and labels are the chart's.
{
  local cfg = $._config,
  local rendered = import 'rendered.json',
  local renderedVersion = importstr 'crds/VERSION',

  // The rendered objects carry a placeholder namespace and the rendered version.
  local retarget(objects) =
    std.parseJson(
      std.strReplace(
        std.strReplace(
          std.strReplace(std.manifestJsonMinified(objects), '__NAMESPACE__', cfg.namespace),
          renderedVersion,
          cfg.version
        ),
        '"app.kubernetes.io/managed-by":"Helm"',
        '"app.kubernetes.io/managed-by":"Tanka"'
      )
    ),
  local objects = retarget(rendered),

  local components = {
    'deployment-cert-manager': 'controller',
    'deployment-cert-manager-webhook': 'webhook',
    'deployment-cert-manager-cainjector': 'cainjector',
  },

  local patchDeployment(key, deployment) = deployment {
    spec+: {
      replicas: cfg.replicas[key],
      template+: {
        spec+: {
          containers: [
            c {
              args+: cfg.extraArgs[key],
            } + (if std.objectHas(cfg.resources, key) then { resources: cfg.resources[key] } else {})
            for c in deployment.spec.template.spec.containers
          ],
        } + (if std.length(cfg.nodeSelector) > 0 then { nodeSelector: cfg.nodeSelector } else {})
        + (if std.length(cfg.tolerations) > 0 then { tolerations: cfg.tolerations } else {}),
      },
    },
  },

  cmObjects: {
    [k]: if std.objectHas(components, k) then patchDeployment(components[k], objects[k]) else objects[k]
    for k in std.objectFields(objects)
    if cfg.webhookNetworkPolicy || objects[k].kind != 'NetworkPolicy'
  },

  cmCrds: if cfg.installCRDs then import 'crds/main.libsonnet' else {},

  cmNamespace: if cfg.createNamespace then {
    apiVersion: 'v1',
    kind: 'Namespace',
    metadata: { name: cfg.namespace },
  } else {},
}
