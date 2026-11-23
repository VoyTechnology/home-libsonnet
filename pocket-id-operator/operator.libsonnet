local k = import 'k.libsonnet';

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

  local rbac = k.rbac.v1,
  // The labels and namespace for a namespaced object of the type `t`; cluster-scoped objects pass `false`.
  local meta(t, namespaced=true) =
    t.metadata.withLabels(labels) + (if namespaced then t.metadata.withNamespace(ns) else {}),
  local rule(apiGroups, resources, verbs) =
    rbac.policyRule.withApiGroups(apiGroups) + rbac.policyRule.withResources(resources) + rbac.policyRule.withVerbs(verbs),

  pidNamespace:
    if cfg.createNamespace then
      k.core.v1.namespace.new(ns)
      // Never prune the namespace, and so its volumes, when the app is removed.
      + k.core.v1.namespace.metadata.withAnnotations({ 'kustomize.toolkit.fluxcd.io/prune': 'disabled' })
    else {},

  pidCrds: if cfg.installCRDs then (import 'crds/main.libsonnet') else {},

  pidServiceAccount: k.core.v1.serviceAccount.new(name) + meta(k.core.v1.serviceAccount),

  pidLeaderElectionRole:
    rbac.role.new(name + '-leader-election-role')
    + meta(rbac.role)
    + rbac.role.withRules([
      rule([''], ['configmaps'], ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete']),
      rule(['coordination.k8s.io'], ['leases'], ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete']),
      rule([''], ['events'], ['create', 'patch']),
    ]),

  pidLeaderElectionRoleBinding:
    rbac.roleBinding.new(name + '-leader-election-rolebinding')
    + meta(rbac.roleBinding)
    + rbac.roleBinding.bindRole($.pidLeaderElectionRole)
    + rbac.roleBinding.withSubjects([rbac.subject.fromServiceAccount($.pidServiceAccount)]),

  pidManagerClusterRole:
    rbac.clusterRole.new(name + '-manager-role')
    + meta(rbac.clusterRole, false)
    + rbac.clusterRole.withRules([
      rule([''], ['configmaps'], ['get']),
      rule([''], ['persistentvolumeclaims', 'secrets', 'services'], crud),
      rule(['apps'], ['deployments', 'statefulsets'], crud),
      rule(['gateway.networking.k8s.io'], ['httproutes'], crud),
      rule(['pocketid.internal'], pocketidResources, crud),
      rule(['pocketid.internal'], [r + '/finalizers' for r in pocketidResources], ['update']),
      rule(['pocketid.internal'], [r + '/status' for r in pocketidResources], ['get', 'patch', 'update']),
    ]),

  pidManagerClusterRoleBinding:
    rbac.clusterRoleBinding.new(name + '-manager-rolebinding')
    + meta(rbac.clusterRoleBinding, false)
    + rbac.clusterRoleBinding.bindRole($.pidManagerClusterRole)
    + rbac.clusterRoleBinding.withSubjects([rbac.subject.fromServiceAccount($.pidServiceAccount)]),

  pidMetricsService:
    local svc = k.core.v1.service;
    local port = k.core.v1.servicePort;
    svc.new(name + '-metrics-service', selector, [port.withName('http') + port.withPort(8080) + port.withProtocol('TCP') + port.withTargetPort(8080)])
    + meta(svc)
    + svc.metadata.withLabelsMixin({ 'control-plane': 'controller-manager' }),

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

  pidDeployment:
    local d = k.apps.v1.deployment;
    local pod = d.spec.template.spec;
    d.new(name, cfg.replicas, [$.manager_container])
    + meta(d)
    + d.metadata.withLabelsMixin({ 'control-plane': 'controller-manager' })
    // new() would add a `name` label; the selector is immutable and must stay as it was.
    + d.spec.selector.withMatchLabels(selector)
    + d.spec.template.metadata.withLabels(selector)
    + d.spec.template.metadata.withAnnotations({ 'kubectl.kubernetes.io/default-container': 'manager' })
    + pod.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.withNodeSelectorTerms([{ matchExpressions: [
      { key: 'kubernetes.io/arch', operator: 'In', values: ['amd64', 'arm64'] },
      { key: 'kubernetes.io/os', operator: 'In', values: ['linux'] },
    ] }])
    + pod.securityContext.withRunAsNonRoot(true)
    + pod.securityContext.seccompProfile.withType('RuntimeDefault')
    + pod.withServiceAccountName(name)
    + pod.withTerminationGracePeriodSeconds(10)
    + (if std.length(cfg.nodeSelector) > 0 then pod.withNodeSelector(cfg.nodeSelector) else {})
    + (if std.length(cfg.tolerations) > 0 then pod.withTolerations(cfg.tolerations) else {}),
}
