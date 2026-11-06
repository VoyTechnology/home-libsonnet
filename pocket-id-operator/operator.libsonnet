// pocket-id-operator (https://github.com/aclerici38/pocket-id-operator), modelled on the
// release's install.yaml: the manager Deployment, its RBAC and metrics Service, plus the
// vendored CRDs (see generate.sh). Object names are the release's. Only the namespace is
// configurable (the release hardcodes pocket-id-operator-system).
{
  local cfg = $._config,
  local ns = cfg.namespace,
  // The image tag is the version; CRDs are vendored for the same one (see crds/VERSION).
  local version = std.reverse(std.split(std.split($._images.operator, '@')[0], ':'))[0],

  // Selectors are immutable. Never change these.
  local selector = {
    'app.kubernetes.io/name': 'pocket-id-operator',
    'control-plane': 'controller-manager',
  },
  local labels = { 'app.kubernetes.io/name': 'pocket-id-operator', 'app.kubernetes.io/version': version, 'app.kubernetes.io/managed-by': 'Tanka' },
  local name = 'pocket-id-operator',
  local crud = ['create', 'delete', 'get', 'list', 'patch', 'update', 'watch'],
  local pocketidResources = ['pocketidapis', 'pocketidinstances', 'pocketidoidcclients', 'pocketidusergroups', 'pocketidusers'],

  pidNamespace:
    if cfg.createNamespace then {
      apiVersion: 'v1',
      kind: 'Namespace',
      metadata: {
        name: ns,
        // Never prune the namespace, and so its volumes, when the app is removed.
        annotations: { 'kustomize.toolkit.fluxcd.io/prune': 'disabled' },
      },
    } else {},

  pidCrds: if cfg.installCRDs then (import 'crds/main.libsonnet') else {},

  pidServiceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: { name: name, namespace: ns, labels: labels },
  },

  pidLeaderElectionRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'Role',
    metadata: { name: name + '-leader-election-role', namespace: ns, labels: labels },
    rules: [
      { apiGroups: [''], resources: ['configmaps'], verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'] },
      { apiGroups: ['coordination.k8s.io'], resources: ['leases'], verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'] },
      { apiGroups: [''], resources: ['events'], verbs: ['create', 'patch'] },
    ],
  },

  pidLeaderElectionRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'RoleBinding',
    metadata: { name: name + '-leader-election-rolebinding', namespace: ns, labels: labels },
    roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'Role', name: $.pidLeaderElectionRole.metadata.name },
    subjects: [{ kind: 'ServiceAccount', name: name, namespace: ns }],
  },

  pidManagerClusterRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: { name: name + '-manager-role', labels: labels },
    rules: [
      { apiGroups: [''], resources: ['configmaps'], verbs: ['get'] },
      { apiGroups: [''], resources: ['persistentvolumeclaims', 'secrets', 'services'], verbs: crud },
      { apiGroups: ['apps'], resources: ['deployments', 'statefulsets'], verbs: crud },
      { apiGroups: ['gateway.networking.k8s.io'], resources: ['httproutes'], verbs: crud },
      { apiGroups: ['pocketid.internal'], resources: pocketidResources, verbs: crud },
      { apiGroups: ['pocketid.internal'], resources: [r + '/finalizers' for r in pocketidResources], verbs: ['update'] },
      { apiGroups: ['pocketid.internal'], resources: [r + '/status' for r in pocketidResources], verbs: ['get', 'patch', 'update'] },
    ],
  },

  pidManagerClusterRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: { name: name + '-manager-rolebinding', labels: labels },
    roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'ClusterRole', name: $.pidManagerClusterRole.metadata.name },
    subjects: [{ kind: 'ServiceAccount', name: name, namespace: ns }],
  },

  pidMetricsService: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: { name: name + '-metrics-service', namespace: ns, labels: labels { 'control-plane': 'controller-manager' } },
    spec: {
      ports: [{ name: 'http', port: 8080, protocol: 'TCP', targetPort: 8080 }],
      selector: selector,
    },
  },

  // The manager container; extend with a mixin (`args+:`, `env+:`, `resources+:`, ...).
  manager_container:: {
    name: 'manager',
    image: $._images.operator,
    command: ['/manager'],
    args: ['--metrics-bind-address=:8080', '--leader-elect', '--health-probe-bind-address=:8081', '--zap-log-level=info'],
    livenessProbe: { httpGet: { path: '/healthz', port: 8081 }, initialDelaySeconds: 15, periodSeconds: 20 },
    readinessProbe: { httpGet: { path: '/readyz', port: 8081 }, initialDelaySeconds: 5, periodSeconds: 10 },
    resources: { limits: { memory: '128Mi' }, requests: { cpu: '10m', memory: '64Mi' } },
    securityContext: {
      allowPrivilegeEscalation: false,
      capabilities: { drop: ['ALL'] },
      readOnlyRootFilesystem: true,
    },
  },

  pidDeployment: {
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: { name: name, namespace: ns, labels: labels { 'control-plane': 'controller-manager' } },
    spec: {
      replicas: cfg.replicas,
      selector: { matchLabels: selector },
      template: {
        metadata: {
          annotations: { 'kubectl.kubernetes.io/default-container': 'manager' },
          labels: selector,
        },
        spec: {
                affinity: { nodeAffinity: { requiredDuringSchedulingIgnoredDuringExecution: { nodeSelectorTerms: [{ matchExpressions: [
                  { key: 'kubernetes.io/arch', operator: 'In', values: ['amd64', 'arm64'] },
                  { key: 'kubernetes.io/os', operator: 'In', values: ['linux'] },
                ] }] } } },
                containers: [$.manager_container],
                securityContext: { runAsNonRoot: true, seccompProfile: { type: 'RuntimeDefault' } },
                serviceAccountName: name,
                terminationGracePeriodSeconds: 10,
              } + (if std.length(cfg.nodeSelector) > 0 then { nodeSelector: cfg.nodeSelector } else {})
              + (if std.length(cfg.tolerations) > 0 then { tolerations: cfg.tolerations } else {}),
      },
    },
  },
}
