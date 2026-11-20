local k = import 'k.libsonnet';

// cloudflare-gateway-controller (https://github.com/matheuscscp/cloudflare-gateway-controller), modelled on
// the Deployment, RBAC and CRDs of its Helm chart (the project ships no plain manifests). The Gateway API
// CRDs and admission policy the chart bundles are left out, whatever provides the Gateway API owns them.
// Names are the chart's with the release name `cloudflare-gateway-controller`.
{
  local cfg = $._config,
  local ns = cfg.namespace,
  // The image tag is the version; CRDs are vendored for the same one (see crds/VERSION).
  local version = std.reverse(std.split(std.split($._images.controller, '@')[0], ':'))[0],

  // Selectors are immutable. Never change these.
  local name = 'cloudflare-gateway-controller',
  local selector = { 'app.kubernetes.io/name': name },
  local labels = selector { 'app.kubernetes.io/version': version, 'app.kubernetes.io/managed-by': 'Tanka' },
  local crud = ['create', 'delete', 'get', 'list', 'patch', 'update', 'watch'],
  local gw = 'gateway.networking.k8s.io',

  local rbac = k.rbac.v1,
  // The labels and namespace for a namespaced object of the type `t`; cluster-scoped objects pass `false`.
  local meta(t, namespaced=true) =
    t.metadata.withLabels(labels) + (if namespaced then t.metadata.withNamespace(ns) else {}),
  local rule(apiGroups, resources, verbs) =
    rbac.policyRule.withApiGroups(apiGroups) + rbac.policyRule.withResources(resources) + rbac.policyRule.withVerbs(verbs),

  cgcNamespace:
    if cfg.createNamespace then
      k.core.v1.namespace.new(ns)
      // Never prune the namespace when the app is removed.
      + k.core.v1.namespace.metadata.withAnnotations({ 'kustomize.toolkit.fluxcd.io/prune': 'disabled' })
    else {},

  cgcCrds: if cfg.installCRDs then (import 'crds/main.libsonnet') else {},

  cgcServiceAccount: k.core.v1.serviceAccount.new(name) + meta(k.core.v1.serviceAccount),

  cgcLeaderElectionRole:
    rbac.role.new(name + '-leader-election')
    + meta(rbac.role)
    + rbac.role.withRules([
      rule(['coordination.k8s.io'], ['leases'], crud),
      rule([''], ['events'], ['create', 'patch']),
    ]),

  cgcLeaderElectionRoleBinding:
    rbac.roleBinding.new(name + '-leader-election')
    + meta(rbac.roleBinding)
    + rbac.roleBinding.bindRole($.cgcLeaderElectionRole)
    + rbac.roleBinding.withSubjects([rbac.subject.fromServiceAccount($.cgcServiceAccount)]),

  cgcClusterRole:
    rbac.clusterRole.new(name)
    + meta(rbac.clusterRole, false)
    + rbac.clusterRole.withRules([
      rule([''], ['configmaps', 'secrets', 'serviceaccounts'], crud),
      rule([''], ['namespaces'], ['get', 'list', 'watch']),
      rule(['apiextensions.k8s.io'], ['customresourcedefinitions'], ['get', 'list', 'watch']),
      rule(['apps'], ['deployments'], crud),
      rule(['autoscaling.k8s.io'], ['verticalpodautoscalers'], crud),
      rule(['cloudflare-gateway-controller.io'], ['cloudflaregatewayparameters'], ['get', 'list', 'watch']),
      rule(['cloudflare-gateway-controller.io'], ['cloudflaregatewaystatuses'], crud),
      rule(['cloudflare-gateway-controller.io'], ['cloudflaregatewaystatuses/status'], ['get', 'patch', 'update']),
      rule(['events.k8s.io'], ['events'], ['create', 'patch']),
      rule([gw], ['gatewayclasses', 'gateways'], ['get', 'list', 'patch', 'update', 'watch']),
      rule([gw], ['gatewayclasses/finalizers', 'gateways/finalizers'], ['update']),
      rule([gw], ['gatewayclasses/status'], ['get', 'patch', 'update']),
      rule([gw], ['gateways/status', 'grpcroutes/status', 'httproutes/status'], ['patch', 'update']),
      rule([gw], ['grpcroutes', 'httproutes'], ['get', 'list', 'update', 'watch']),
      rule([gw], ['referencegrants'], ['get', 'list', 'watch']),
      rule(['rbac.authorization.k8s.io'], ['rolebindings', 'roles'], crud),
    ]),

  cgcClusterRoleBinding:
    rbac.clusterRoleBinding.new(name)
    + meta(rbac.clusterRoleBinding, false)
    + rbac.clusterRoleBinding.bindRole($.cgcClusterRole)
    + rbac.clusterRoleBinding.withSubjects([rbac.subject.fromServiceAccount($.cgcServiceAccount)]),

  // The controller container; extend with a mixin (`args+:`, `env+:`, `resources+:`, ...).
  controller_container:: {
    name: 'controller',
    image: $._images.controller,
    args: [
      'controller',
      '--cluster-name=' + cfg.clusterName,
      '--tunnel-image=' + $._images.controller,
    ],
    ports: [
      { name: 'metrics', containerPort: 8080, protocol: 'TCP' },
      { name: 'health', containerPort: 8081, protocol: 'TCP' },
    ],
    livenessProbe: { httpGet: { path: '/healthz', port: 'health' } },
    readinessProbe: { httpGet: { path: '/readyz', port: 'health' } },
    resources: { limits: { cpu: '500m', memory: '128Mi' }, requests: { cpu: '10m', memory: '64Mi' } },
    securityContext: {
      allowPrivilegeEscalation: false,
      capabilities: { drop: ['ALL'] },
      readOnlyRootFilesystem: true,
    },
  },

  cgcDeployment:
    local d = k.apps.v1.deployment;
    local pod = d.spec.template.spec;
    d.new(name, cfg.replicas, [$.controller_container])
    + meta(d)
    + d.metadata.withLabelsMixin({ 'cloudflare-gateway-controller.io/component': 'controller' })
    // new() would add a `name` label; the selector is immutable and must stay as it was.
    + d.spec.selector.withMatchLabels(selector)
    + d.spec.template.metadata.withLabels(selector)
    + pod.securityContext.withRunAsNonRoot(true)
    + pod.securityContext.seccompProfile.withType('RuntimeDefault')
    + pod.withServiceAccountName(name)
    + pod.withTerminationGracePeriodSeconds(10)
    + (if std.length(cfg.nodeSelector) > 0 then pod.withNodeSelector(cfg.nodeSelector) else {})
    + (if std.length(cfg.tolerations) > 0 then pod.withTolerations(cfg.tolerations) else {}),
}
