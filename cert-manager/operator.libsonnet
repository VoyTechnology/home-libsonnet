local k = import 'k.libsonnet';

// cert-manager, modelled on the upstream Helm chart's default rendering: controller,
// webhook and cainjector Deployments with their RBAC, Services, webhook
// configurations and NetworkPolicies, plus the vendored CRDs (see generate.sh).
// Object names are the chart's, so it can replace a Helm install in place.
{
  local cfg = $._config,
  local ns = cfg.namespace,
  // Leader election leases live here, as in the chart.
  local leaderNs = 'kube-system',
  // The image tag is the version; CRDs are vendored for the same one (see crds/VERSION).
  local version = std.reverse(std.split($._images.controller, ':'))[0],

  local components = {
    controller: { name: 'cert-manager', label: 'cert-manager', component: 'controller' },
    cainjector: { name: 'cert-manager-cainjector', label: 'cainjector', component: 'cainjector' },
    webhook: { name: 'cert-manager-webhook', label: 'webhook', component: 'webhook' },
  },

  // Selectors are immutable. Never change these.
  local selector(c) = {
    'app.kubernetes.io/name': c.label,
    'app.kubernetes.io/instance': 'cert-manager',
    'app.kubernetes.io/component': c.component,
  },
  // Metadata labels, free to change.
  local labels(c) = selector(c) + {
    app: c.label,
    'app.kubernetes.io/version': version,
    'app.kubernetes.io/managed-by': 'Tanka',
  },
  local rbac = k.rbac.v1,
  // The labels, and the namespace if there is one, for an object of the type `t`.
  local meta(t, c, namespace=null) =
    t.metadata.withLabels(labels(c))
    + (if namespace != null then t.metadata.withNamespace(namespace) else {}),

  local role(name, c, rules, kind='ClusterRole', namespace=null, extraLabels={}) =
    local t = if kind == 'Role' then rbac.role else rbac.clusterRole;
    t.new(name) + meta(t, c, namespace) + t.metadata.withLabelsMixin(extraLabels) + t.withRules(rules),
  local binding(name, c, roleName, serviceAccount, kind='ClusterRole', namespace=null) =
    local t = if kind == 'Role' then rbac.roleBinding else rbac.clusterRoleBinding;
    t.new(name)
    + meta(t, c, namespace)
    + t.roleRef.withApiGroup('rbac.authorization.k8s.io')
    + t.roleRef.withKind(kind)
    + t.roleRef.withName(roleName)
    + t.withSubjects([rbac.subject.withKind('ServiceAccount') + rbac.subject.withName(serviceAccount) + rbac.subject.withNamespace(ns)]),

  local rule(apiGroups, resources, verbs, resourceNames=null) =
    rbac.policyRule.withApiGroups(apiGroups)
    + rbac.policyRule.withResources(resources)
    + rbac.policyRule.withVerbs(verbs)
    + (if resourceNames != null then rbac.policyRule.withResourceNames(resourceNames) else {}),
  local events = rule([''], ['events'], ['create', 'patch']),
  local readSecrets = rule([''], ['secrets'], ['get', 'list', 'watch']),
  local signers = ['issuers.cert-manager.io/*', 'clusterissuers.cert-manager.io/*'],

  local serviceAccount(c) =
    k.core.v1.serviceAccount.new(c.name)
    + meta(k.core.v1.serviceAccount, c, ns)
    + k.core.v1.serviceAccount.withAutomountServiceAccountToken(true),

  local container(key, c, args, extra) = {
    name: c.name,
    image: $._images[key],
    imagePullPolicy: 'IfNotPresent',
    args: args,
    env: [{ name: 'POD_NAMESPACE', valueFrom: { fieldRef: { fieldPath: 'metadata.namespace' } } }],
    securityContext: {
      allowPrivilegeEscalation: false,
      capabilities: { drop: ['ALL'] },
      readOnlyRootFilesystem: true,
    },
  } + (if std.objectHas(cfg.resources, key) then { resources: cfg.resources[key] } else {}) + extra,

  local deployment(key, c, podContainer) =
    local d = k.apps.v1.deployment;
    local pod = d.spec.template.spec;
    d.new(c.name, cfg.replicas[key], [podContainer])
    + meta(d, c, ns)
    // new() would add a `name` label; the selector is immutable and must stay as it was.
    + d.spec.selector.withMatchLabels(selector(c))
    + d.spec.template.metadata.withLabels(labels(c))
    + d.spec.template.metadata.withAnnotations({
      'prometheus.io/path': '/metrics',
      'prometheus.io/scrape': 'true',
      'prometheus.io/port': '9402',
    })
    + pod.withServiceAccountName(c.name)
    + pod.withEnableServiceLinks(false)
    + pod.securityContext.withRunAsNonRoot(true)
    + pod.securityContext.seccompProfile.withType('RuntimeDefault')
    + pod.withNodeSelector({ 'kubernetes.io/os': 'linux' } + cfg.nodeSelector)
    + (if std.length(cfg.tolerations) > 0 then pod.withTolerations(cfg.tolerations) else {}),

  local metricsPort = { name: 'http-metrics', containerPort: 9402, protocol: 'TCP' },

  cmNamespace: if cfg.createNamespace then k.core.v1.namespace.new(ns) else {},

  cmCrds: if cfg.installCRDs then import 'crds/main.libsonnet' else {},

  // --- Controller ---
  cmControllerServiceAccount: serviceAccount(components.controller),

  // The controller container. Extend it with a mixin, e.g. `controller_container+:: { args+: ['--v=4'] }`.
  controller_container:: container(
    'controller',
    components.controller { name: 'cert-manager-controller' },
    [
      '--v=2',
      '--cluster-resource-namespace=$(POD_NAMESPACE)',
      '--leader-election-namespace=' + leaderNs,
      '--acme-http01-solver-image=' + $._images.acmesolver,
      '--max-concurrent-challenges=60',
    ],
    {
      ports: [metricsPort, { name: 'http-healthz', containerPort: 9403, protocol: 'TCP' }],
      livenessProbe: {
        httpGet: { port: 'http-healthz', path: '/livez', scheme: 'HTTP' },
        initialDelaySeconds: 10,
        periodSeconds: 10,
        timeoutSeconds: 15,
        successThreshold: 1,
        failureThreshold: 8,
      },
    },
  ),

  cmControllerDeployment: deployment('controller', components.controller, $.controller_container),

  cmControllerService:
    local svc = k.core.v1.service;
    local port = k.core.v1.servicePort;
    svc.new('cert-manager', selector(components.controller), [
      port.withName('tcp-prometheus-servicemonitor') + port.withPort(9402) + port.withTargetPort('http-metrics') + port.withProtocol('TCP'),
    ])
    + meta(svc, components.controller, ns)
    + svc.spec.withType('ClusterIP'),

  cmControllerLeaderElectionRole: role('cert-manager:leaderelection', components.controller, [
    rule(['coordination.k8s.io'], ['leases'], ['get', 'update', 'patch'], ['cert-manager-controller']),
    rule(['coordination.k8s.io'], ['leases'], ['create']),
  ], 'Role', leaderNs),
  cmControllerLeaderElectionRoleBinding: binding('cert-manager:leaderelection', components.controller, 'cert-manager:leaderelection', 'cert-manager', 'Role', leaderNs),

  // The controller requests tokens for its own service account (Vault, etc. issuers).
  cmControllerTokenRequestRole: role('cert-manager-tokenrequest', components.controller, [
    rule([''], ['serviceaccounts/token'], ['create'], ['cert-manager']),
  ], 'Role', ns),
  cmControllerTokenRequestRoleBinding: binding('cert-manager-tokenrequest', components.controller, 'cert-manager-tokenrequest', 'cert-manager', 'Role', ns),

  // One ClusterRole and binding per controller, named cert-manager-controller-<name>.
  local controllerRoles = {
    issuers: [
      rule(['cert-manager.io'], ['issuers', 'issuers/status'], ['update', 'patch']),
      rule(['cert-manager.io'], ['issuers'], ['get', 'list', 'watch']),
      rule([''], ['secrets'], ['get', 'list', 'watch', 'create', 'update', 'delete']),
      events,
    ],
    clusterissuers: [
      rule(['cert-manager.io'], ['clusterissuers', 'clusterissuers/status'], ['update', 'patch']),
      rule(['cert-manager.io'], ['clusterissuers'], ['get', 'list', 'watch']),
      rule([''], ['secrets'], ['get', 'list', 'watch', 'create', 'update', 'delete']),
      events,
    ],
    certificates: [
      rule(['cert-manager.io'], ['certificates', 'certificates/status', 'certificaterequests', 'certificaterequests/status'], ['update', 'patch']),
      rule(['cert-manager.io'], ['certificates', 'certificaterequests', 'clusterissuers', 'issuers'], ['get', 'list', 'watch']),
      rule(['cert-manager.io'], ['certificates/finalizers', 'certificaterequests/finalizers'], ['update']),
      rule(['acme.cert-manager.io'], ['orders'], ['create', 'delete', 'get', 'list', 'watch']),
      rule([''], ['secrets'], ['get', 'list', 'watch', 'create', 'update', 'delete', 'patch']),
      events,
    ],
    orders: [
      rule(['acme.cert-manager.io'], ['orders', 'orders/status'], ['update', 'patch']),
      rule(['acme.cert-manager.io'], ['orders', 'challenges'], ['get', 'list', 'watch']),
      rule(['cert-manager.io'], ['clusterissuers', 'issuers'], ['get', 'list', 'watch']),
      rule(['acme.cert-manager.io'], ['challenges'], ['create', 'delete']),
      rule(['acme.cert-manager.io'], ['orders/finalizers'], ['update']),
      readSecrets,
      events,
    ],
    challenges: [
      rule(['acme.cert-manager.io'], ['challenges', 'challenges/status'], ['update', 'patch']),
      rule(['acme.cert-manager.io'], ['challenges'], ['get', 'list', 'watch']),
      rule(['cert-manager.io'], ['issuers', 'clusterissuers'], ['get', 'list', 'watch']),
      readSecrets,
      events,
      // HTTP01 solver pods, services and routes.
      rule([''], ['pods', 'services'], ['get', 'list', 'watch', 'create', 'delete']),
      rule(['networking.k8s.io'], ['ingresses'], ['get', 'list', 'watch', 'create', 'delete', 'update']),
      rule(['gateway.networking.k8s.io'], ['httproutes'], ['get', 'list', 'watch', 'create', 'delete', 'update']),
      rule(['route.openshift.io'], ['routes/custom-host'], ['create']),
      rule(['acme.cert-manager.io'], ['challenges/finalizers'], ['update']),
      readSecrets,
    ],
    'ingress-shim': [
      rule(['cert-manager.io'], ['certificates', 'certificaterequests'], ['create', 'update', 'delete']),
      rule(['cert-manager.io'], ['certificates', 'certificaterequests', 'issuers', 'clusterissuers'], ['get', 'list', 'watch']),
      rule(['networking.k8s.io'], ['ingresses'], ['get', 'list', 'watch']),
      rule(['networking.k8s.io'], ['ingresses/finalizers'], ['update']),
      rule(['gateway.networking.k8s.io'], ['gateways', 'httproutes'], ['get', 'list', 'watch']),
      rule(['gateway.networking.k8s.io'], ['gateways/finalizers', 'httproutes/finalizers'], ['update']),
      events,
    ],
  },
  cmControllerClusterRoles: {
    ['cert-manager-controller-' + n]: role('cert-manager-controller-' + n, components.controller, controllerRoles[n])
    for n in std.objectFields(controllerRoles)
  },
  cmControllerClusterRoleBindings: {
    ['cert-manager-controller-' + n]: binding('cert-manager-controller-' + n, components.controller, 'cert-manager-controller-' + n, 'cert-manager')
    for n in std.objectFields(controllerRoles)
  },

  // Certificate signing request support. The chart labels these with component `cert-manager`.
  local csrComponent = components.controller { component: 'cert-manager' },
  cmApproveClusterRole: role('cert-manager-controller-approve:cert-manager-io', csrComponent, [
    rule(['cert-manager.io'], ['signers'], ['approve'], signers),
  ]),
  cmApproveClusterRoleBinding: binding('cert-manager-controller-approve:cert-manager-io', csrComponent, 'cert-manager-controller-approve:cert-manager-io', 'cert-manager'),
  cmCertificateSigningRequestsClusterRole: role('cert-manager-controller-certificatesigningrequests', csrComponent, [
    rule(['certificates.k8s.io'], ['certificatesigningrequests'], ['get', 'list', 'watch', 'update']),
    rule(['certificates.k8s.io'], ['certificatesigningrequests/status'], ['update', 'patch']),
    rule(['certificates.k8s.io'], ['signers'], ['sign'], signers),
    rule(['authorization.k8s.io'], ['subjectaccessreviews'], ['create']),
  ]),
  cmCertificateSigningRequestsClusterRoleBinding: binding('cert-manager-controller-certificatesigningrequests', csrComponent, 'cert-manager-controller-certificatesigningrequests', 'cert-manager'),

  // Aggregated into the built-in view, edit, admin and cluster-reader roles.
  cmClusterViewClusterRole: role('cert-manager-cluster-view', components.controller, [
    rule(['cert-manager.io'], ['clusterissuers'], ['get', 'list', 'watch']),
  ], extraLabels={ 'rbac.authorization.k8s.io/aggregate-to-cluster-reader': 'true' }),
  cmViewClusterRole: role('cert-manager-view', components.controller, [
    rule(['cert-manager.io'], ['certificates', 'certificaterequests', 'issuers'], ['get', 'list', 'watch']),
    rule(['acme.cert-manager.io'], ['challenges', 'orders'], ['get', 'list', 'watch']),
  ], extraLabels={
    'rbac.authorization.k8s.io/aggregate-to-view': 'true',
    'rbac.authorization.k8s.io/aggregate-to-edit': 'true',
    'rbac.authorization.k8s.io/aggregate-to-admin': 'true',
    'rbac.authorization.k8s.io/aggregate-to-cluster-reader': 'true',
  }),
  cmEditClusterRole: role('cert-manager-edit', components.controller, [
    rule(['cert-manager.io'], ['certificates', 'certificaterequests', 'issuers'], ['create', 'delete', 'deletecollection', 'patch', 'update']),
    rule(['cert-manager.io'], ['certificates/status'], ['update']),
    rule(['acme.cert-manager.io'], ['challenges', 'orders'], ['create', 'delete', 'deletecollection', 'patch', 'update']),
  ], extraLabels={
    'rbac.authorization.k8s.io/aggregate-to-edit': 'true',
    'rbac.authorization.k8s.io/aggregate-to-admin': 'true',
  }),

  // --- Cainjector: copies the webhook CA into webhook configurations, CRDs and APIServices ---
  cmCainjectorServiceAccount: serviceAccount(components.cainjector),

  // The cainjector container. Extend it with a mixin, e.g. `cainjector_container+:: { args+: ['--v=4'] }`.
  cainjector_container:: container(
    'cainjector',
    components.cainjector,
    ['--v=2', '--leader-election-namespace=' + leaderNs],
    { ports: [metricsPort] },
  ),

  cmCainjectorDeployment: deployment('cainjector', components.cainjector, $.cainjector_container),

  cmCainjectorService:
    local svc = k.core.v1.service;
    local port = k.core.v1.servicePort;
    svc.new('cert-manager-cainjector', selector(components.cainjector), [
      port.withName('http-metrics') + port.withPort(9402) + port.withProtocol('TCP'),
    ])
    + meta(svc, components.cainjector, ns)
    + svc.spec.withType('ClusterIP'),

  cmCainjectorClusterRole: role('cert-manager-cainjector', components.cainjector, [
    rule(['cert-manager.io'], ['certificates'], ['get', 'list', 'watch']),
    readSecrets,
    rule([''], ['events'], ['get', 'create', 'update', 'patch']),
    rule(['admissionregistration.k8s.io'], ['validatingwebhookconfigurations', 'mutatingwebhookconfigurations'], ['get', 'list', 'watch', 'update', 'patch']),
    rule(['apiregistration.k8s.io'], ['apiservices'], ['get', 'list', 'watch', 'update', 'patch']),
    rule(['apiextensions.k8s.io'], ['customresourcedefinitions'], ['get', 'list', 'watch', 'update', 'patch']),
  ]),
  cmCainjectorClusterRoleBinding: binding('cert-manager-cainjector', components.cainjector, 'cert-manager-cainjector', 'cert-manager-cainjector'),

  cmCainjectorLeaderElectionRole: role('cert-manager-cainjector:leaderelection', components.cainjector, [
    rule(['coordination.k8s.io'], ['leases'], ['get', 'update', 'patch'], ['cert-manager-cainjector-leader-election', 'cert-manager-cainjector-leader-election-core']),
    rule(['coordination.k8s.io'], ['leases'], ['create']),
  ], 'Role', leaderNs),
  cmCainjectorLeaderElectionRoleBinding: binding('cert-manager-cainjector:leaderelection', components.cainjector, 'cert-manager-cainjector:leaderelection', 'cert-manager-cainjector', 'Role', leaderNs),

  // --- Webhook: validates and mutates cert-manager resources ---
  cmWebhookServiceAccount: serviceAccount(components.webhook),

  // The webhook container. Extend it with a mixin, e.g. `webhook_container+:: { args+: ['--v=4'] }`.
  webhook_container:: container(
    'webhook',
    components.webhook,
    [
      '--v=2',
      '--secure-port=10250',
      '--dynamic-serving-ca-secret-namespace=$(POD_NAMESPACE)',
      '--dynamic-serving-ca-secret-name=cert-manager-webhook-ca',
      '--dynamic-serving-dns-names=cert-manager-webhook',
      '--dynamic-serving-dns-names=cert-manager-webhook.$(POD_NAMESPACE)',
      '--dynamic-serving-dns-names=cert-manager-webhook.$(POD_NAMESPACE).svc',
    ],
    {
      ports: [
        { name: 'https', containerPort: 10250, protocol: 'TCP' },
        { name: 'healthcheck', containerPort: 6080, protocol: 'TCP' },
        metricsPort,
      ],
      livenessProbe: {
        httpGet: { path: '/livez', port: 'healthcheck', scheme: 'HTTP' },
        initialDelaySeconds: 60,
        periodSeconds: 10,
        timeoutSeconds: 1,
        successThreshold: 1,
        failureThreshold: 3,
      },
      readinessProbe: {
        httpGet: { path: '/healthz', port: 'healthcheck', scheme: 'HTTP' },
        initialDelaySeconds: 5,
        periodSeconds: 5,
        timeoutSeconds: 1,
        successThreshold: 1,
        failureThreshold: 3,
      },
    },
  ),

  cmWebhookDeployment: deployment('webhook', components.webhook, $.webhook_container),

  cmWebhookService:
    local svc = k.core.v1.service;
    local port = k.core.v1.servicePort;
    svc.new('cert-manager-webhook', selector(components.webhook), [
      port.withName('https') + port.withPort(443) + port.withTargetPort('https') + port.withProtocol('TCP'),
      port.withName('metrics') + port.withPort(9402) + port.withTargetPort('http-metrics') + port.withProtocol('TCP'),
    ])
    + meta(svc, components.webhook, ns)
    + svc.spec.withType('ClusterIP'),

  // The webhook issues its own serving certificate into this Secret.
  cmWebhookDynamicServingRole: role('cert-manager-webhook:dynamic-serving', components.webhook, [
    rule([''], ['secrets'], ['get', 'list', 'watch', 'update'], ['cert-manager-webhook-ca']),
    rule([''], ['secrets'], ['create']),
  ], 'Role', ns),
  cmWebhookDynamicServingRoleBinding: binding('cert-manager-webhook:dynamic-serving', components.webhook, 'cert-manager-webhook:dynamic-serving', 'cert-manager-webhook', 'Role', ns),

  cmWebhookSubjectAccessReviewsClusterRole: role('cert-manager-webhook:subjectaccessreviews', components.webhook, [
    rule(['authorization.k8s.io'], ['subjectaccessreviews'], ['create']),
  ]),
  cmWebhookSubjectAccessReviewsClusterRoleBinding: binding('cert-manager-webhook:subjectaccessreviews', components.webhook, 'cert-manager-webhook:subjectaccessreviews', 'cert-manager-webhook'),

  local webhookConfig(t, webhook) =
    t.new('cert-manager-webhook')
    + meta(t, components.webhook)
    + t.metadata.withAnnotations({ 'cert-manager.io/inject-ca-from-secret': '%s/cert-manager-webhook-ca' % ns })
    + t.withWebhooks([{
      name: 'webhook.cert-manager.io',
      admissionReviewVersions: ['v1'],
      matchPolicy: 'Equivalent',
      timeoutSeconds: 30,
      failurePolicy: 'Fail',
      sideEffects: 'None',
      clientConfig: { service: { name: 'cert-manager-webhook', namespace: ns, path: webhook.path } },
    } + webhook.extra]),

  cmMutatingWebhook: webhookConfig(k.admissionregistration.v1.mutatingWebhookConfiguration, {
    path: '/mutate',
    extra: {
      rules: [{ apiGroups: ['cert-manager.io'], apiVersions: ['v1'], operations: ['CREATE'], resources: ['certificaterequests'] }],
    },
  }),
  cmValidatingWebhook: webhookConfig(k.admissionregistration.v1.validatingWebhookConfiguration, {
    path: '/validate',
    extra: {
      namespaceSelector: { matchExpressions: [{ key: 'cert-manager.io/disable-validation', operator: 'NotIn', values: ['true'] }] },
      rules: [{ apiGroups: ['cert-manager.io', 'acme.cert-manager.io'], apiVersions: ['v1'], operations: ['CREATE', 'UPDATE'], resources: ['*/*'] }],
    },
  }),

  // Egress to the API server, ACME and DNS; ingress from the API server for admission.
  local anywhere = [{ ipBlock: { cidr: '0.0.0.0/0' } }, { ipBlock: { cidr: '::/0' } }],
  local webhookPolicy(name, policyType, spec) =
    local np = k.networking.v1.networkPolicy;
    np.new(name)
    + np.metadata.withNamespace(ns)
    + np.spec.podSelector.withMatchLabels(selector(components.webhook))
    + np.spec.withPolicyTypes([policyType])
    + { spec+: spec },
  cmWebhookNetworkPolicies: if cfg.webhookNetworkPolicy then {
    egress: webhookPolicy('cert-manager-webhook-allow-egress', 'Egress', {
      egress: [{
        ports: [
          { port: 80, protocol: 'TCP' },
          { port: 443, protocol: 'TCP' },
          { port: 53, protocol: 'TCP' },
          { port: 53, protocol: 'UDP' },
          { port: 6443, protocol: 'TCP' },
        ],
        to: anywhere,
      }],
    }),
    ingress: webhookPolicy('cert-manager-webhook-allow-ingress', 'Ingress', {
      ingress: [{ from: anywhere }],
    }),
  } else {},
}
