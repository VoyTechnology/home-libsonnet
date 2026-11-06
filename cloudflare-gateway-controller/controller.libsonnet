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

  cgcNamespace:
    if cfg.createNamespace then {
      apiVersion: 'v1',
      kind: 'Namespace',
      metadata: {
        name: ns,
        // Never prune the namespace when the app is removed.
        annotations: { 'kustomize.toolkit.fluxcd.io/prune': 'disabled' },
      },
    } else {},

  cgcCrds: if cfg.installCRDs then (import 'crds/main.libsonnet') else {},

  cgcServiceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: { name: name, namespace: ns, labels: labels },
  },

  cgcLeaderElectionRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'Role',
    metadata: { name: name + '-leader-election', namespace: ns, labels: labels },
    rules: [
      { apiGroups: ['coordination.k8s.io'], resources: ['leases'], verbs: crud },
      { apiGroups: [''], resources: ['events'], verbs: ['create', 'patch'] },
    ],
  },

  cgcLeaderElectionRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'RoleBinding',
    metadata: { name: name + '-leader-election', namespace: ns, labels: labels },
    roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'Role', name: $.cgcLeaderElectionRole.metadata.name },
    subjects: [{ kind: 'ServiceAccount', name: name, namespace: ns }],
  },

  cgcClusterRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: { name: name, labels: labels },
    rules: [
      { apiGroups: [''], resources: ['configmaps', 'secrets', 'serviceaccounts'], verbs: crud },
      { apiGroups: [''], resources: ['namespaces'], verbs: ['get', 'list', 'watch'] },
      { apiGroups: ['apiextensions.k8s.io'], resources: ['customresourcedefinitions'], verbs: ['get', 'list', 'watch'] },
      { apiGroups: ['apps'], resources: ['deployments'], verbs: crud },
      { apiGroups: ['autoscaling.k8s.io'], resources: ['verticalpodautoscalers'], verbs: crud },
      { apiGroups: ['cloudflare-gateway-controller.io'], resources: ['cloudflaregatewayparameters'], verbs: ['get', 'list', 'watch'] },
      { apiGroups: ['cloudflare-gateway-controller.io'], resources: ['cloudflaregatewaystatuses'], verbs: crud },
      { apiGroups: ['cloudflare-gateway-controller.io'], resources: ['cloudflaregatewaystatuses/status'], verbs: ['get', 'patch', 'update'] },
      { apiGroups: ['events.k8s.io'], resources: ['events'], verbs: ['create', 'patch'] },
      { apiGroups: [gw], resources: ['gatewayclasses', 'gateways'], verbs: ['get', 'list', 'patch', 'update', 'watch'] },
      { apiGroups: [gw], resources: ['gatewayclasses/finalizers', 'gateways/finalizers'], verbs: ['update'] },
      { apiGroups: [gw], resources: ['gatewayclasses/status'], verbs: ['get', 'patch', 'update'] },
      { apiGroups: [gw], resources: ['gateways/status', 'grpcroutes/status', 'httproutes/status'], verbs: ['patch', 'update'] },
      { apiGroups: [gw], resources: ['grpcroutes', 'httproutes'], verbs: ['get', 'list', 'update', 'watch'] },
      { apiGroups: [gw], resources: ['referencegrants'], verbs: ['get', 'list', 'watch'] },
      { apiGroups: ['rbac.authorization.k8s.io'], resources: ['rolebindings', 'roles'], verbs: crud },
    ],
  },

  cgcClusterRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: { name: name, labels: labels },
    roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'ClusterRole', name: $.cgcClusterRole.metadata.name },
    subjects: [{ kind: 'ServiceAccount', name: name, namespace: ns }],
  },

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

  cgcDeployment: {
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: { name: name, namespace: ns, labels: labels { 'cloudflare-gateway-controller.io/component': 'controller' } },
    spec: {
      replicas: cfg.replicas,
      selector: { matchLabels: selector },
      template: {
        metadata: { labels: selector },
        spec: {
                containers: [$.controller_container],
                securityContext: { runAsNonRoot: true, seccompProfile: { type: 'RuntimeDefault' } },
                serviceAccountName: name,
                terminationGracePeriodSeconds: 10,
              } + (if std.length(cfg.nodeSelector) > 0 then { nodeSelector: cfg.nodeSelector } else {})
              + (if std.length(cfg.tolerations) > 0 then { tolerations: cfg.tolerations } else {}),
      },
    },
  },
}
