// External Secrets Operator, modelled on the upstream Helm chart's default
// rendering: controller, webhook and cert-controller Deployments with their
// RBAC, the webhook Service/Secret/ValidatingWebhookConfigurations, and the
// vendored CRDs (see generate-crds.sh).
{
  local cfg = $._config,
  local ns = cfg.namespace,
  local fullname = cfg.name,
  // The image tag is the version; CRDs are vendored for the same one (see crds/VERSION).
  local version = std.reverse(std.split($._images.externalSecrets, ':'))[0],
  local webhookName = '%s-webhook' % cfg.name,
  local certName = '%s-cert-controller' % cfg.name,

  // Selectors are immutable. Never change these.
  local selector(component) = {
    'app.kubernetes.io/name': component,
    'app.kubernetes.io/instance': cfg.name,
  },
  // Metadata labels, free to change.
  local labels(component) = selector(component) + {
    'app.kubernetes.io/version': version,
    'app.kubernetes.io/managed-by': 'Tanka',
  },
  local meta(name, component, namespaced=true) = {
    name: name,
    labels: labels(component),
  } + (if namespaced then { namespace: ns } else {}),

  local container(component, key, args, extra) = {
    name: component,
    image: $._images.externalSecrets,
    imagePullPolicy: cfg.imagePullPolicy,
    securityContext: {
      allowPrivilegeEscalation: false,
      capabilities: { drop: ['ALL'] },
      readOnlyRootFilesystem: true,
      runAsNonRoot: true,
      runAsUser: 1000,
      seccompProfile: { type: 'RuntimeDefault' },
    },
    args: args,
    ports: [{ name: 'metrics', containerPort: 8080, protocol: 'TCP' }],
  } + (if std.objectHas(cfg.resources, key) then { resources: cfg.resources[key] } else {}) + extra,

  local readiness = {
    readinessProbe: {
      httpGet: { port: 8081, path: '/readyz' },
      initialDelaySeconds: 20,
      periodSeconds: 5,
    },
  },

  local deployment(name, component, key, serviceAccount, podSpec) = {
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: meta(name, component),
    spec: {
      replicas: cfg.replicas[key],
      revisionHistoryLimit: 10,
      selector: { matchLabels: selector(component) },
      template: {
        metadata: { labels: labels(component) },
        spec: {
                serviceAccountName: serviceAccount,
                automountServiceAccountToken: true,
                hostNetwork: false,
              } + podSpec
              + (if std.length(cfg.nodeSelector) > 0 then { nodeSelector: cfg.nodeSelector } else {})
              + (if std.length(cfg.tolerations) > 0 then { tolerations: cfg.tolerations } else {}),
      },
    },
  },

  local serviceAccount(name, component) = {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: meta(name, component),
  },

  local common = ['--metrics-addr=:8080', '--loglevel=' + cfg.logLevel, '--zap-time-encoding=epoch'],

  // Empty objects are skipped by Tanka.
  esNamespace: if cfg.createNamespace then {
    apiVersion: 'v1',
    kind: 'Namespace',
    metadata: { name: ns, labels: labels('external-secrets') },
  } else {},

  esCrds: if cfg.installCRDs then (import 'crds/main.libsonnet') else {},

  // --- Controller ---
  esServiceAccount: serviceAccount(fullname, 'external-secrets'),

  esDeployment: deployment(fullname, 'external-secrets', 'controller', fullname, {
    containers: [container(
      'external-secrets',
      'controller',
      ['--concurrent=%d' % cfg.concurrent] + common + cfg.extraArgs.controller,
      {},
    )],
    dnsPolicy: 'ClusterFirst',
  }),

  esControllerClusterRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: meta('%s-controller' % fullname, 'external-secrets', false),
    rules: [
      {
        apiGroups: ['external-secrets.io'],
        resources: ['secretstores', 'clustersecretstores', 'externalsecrets', 'clusterexternalsecrets', 'pushsecrets', 'clusterpushsecrets'],
        verbs: ['get', 'list', 'watch'],
      },
      {
        apiGroups: ['external-secrets.io'],
        resources: [
          r + s
          for r in ['externalsecrets', 'secretstores', 'clustersecretstores', 'clusterexternalsecrets', 'pushsecrets', 'clusterpushsecrets']
          for s in ['', '/status', '/finalizers']
        ],
        verbs: ['get', 'update', 'patch'],
      },
      {
        apiGroups: ['generators.external-secrets.io'],
        resources: ['generatorstates'],
        verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete', 'deletecollection'],
      },
      {
        apiGroups: ['generators.external-secrets.io'],
        resources: ['acraccesstokens', 'clustergenerators', 'ecrauthorizationtokens', 'fakes', 'gcraccesstokens', 'githubaccesstokens', 'quayaccesstokens', 'passwords', 'stssessiontokens', 'uuids', 'vaultdynamicsecrets', 'webhooks', 'grafanas', 'mfas'],
        verbs: ['get', 'list', 'watch'],
      },
      { apiGroups: [''], resources: ['serviceaccounts', 'namespaces'], verbs: ['get', 'list', 'watch'] },
      { apiGroups: [''], resources: ['configmaps'], verbs: ['get', 'list', 'watch'] },
      { apiGroups: [''], resources: ['secrets'], verbs: ['get', 'list', 'watch', 'create', 'update', 'delete', 'patch'] },
      { apiGroups: [''], resources: ['serviceaccounts/token'], verbs: ['create'] },
      { apiGroups: [''], resources: ['events'], verbs: ['create', 'patch'] },
      { apiGroups: ['external-secrets.io'], resources: ['externalsecrets'], verbs: ['create', 'update', 'delete'] },
      { apiGroups: ['external-secrets.io'], resources: ['pushsecrets'], verbs: ['create', 'update', 'delete'] },
    ],
  },

  esControllerClusterRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: meta('%s-controller' % fullname, 'external-secrets', false),
    roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'ClusterRole', name: '%s-controller' % fullname },
    subjects: [{ kind: 'ServiceAccount', name: fullname, namespace: ns }],
  },

  local generatorResources = ['acraccesstokens', 'clustergenerators', 'ecrauthorizationtokens', 'fakes', 'gcraccesstokens', 'githubaccesstokens', 'quayaccesstokens', 'passwords', 'vaultdynamicsecrets', 'webhooks', 'grafanas', 'generatorstates', 'mfas'],
  local userResources = ['externalsecrets', 'secretstores', 'clustersecretstores', 'pushsecrets', 'clusterpushsecrets'],

  // Aggregated into the built-in view/edit/admin roles.
  esViewClusterRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: meta('%s-view' % fullname, 'external-secrets', false) {
      labels+: {
        'rbac.authorization.k8s.io/aggregate-to-view': 'true',
        'rbac.authorization.k8s.io/aggregate-to-edit': 'true',
        'rbac.authorization.k8s.io/aggregate-to-admin': 'true',
      },
    },
    rules: [
      { apiGroups: ['external-secrets.io'], resources: userResources, verbs: ['get', 'watch', 'list'] },
      { apiGroups: ['generators.external-secrets.io'], resources: generatorResources, verbs: ['get', 'watch', 'list'] },
    ],
  },

  esEditClusterRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: meta('%s-edit' % fullname, 'external-secrets', false) {
      labels+: {
        'rbac.authorization.k8s.io/aggregate-to-edit': 'true',
        'rbac.authorization.k8s.io/aggregate-to-admin': 'true',
      },
    },
    rules: [
      { apiGroups: ['external-secrets.io'], resources: userResources, verbs: ['create', 'delete', 'deletecollection', 'patch', 'update'] },
      { apiGroups: ['generators.external-secrets.io'], resources: generatorResources, verbs: ['create', 'delete', 'deletecollection', 'patch', 'update'] },
    ],
  },

  esServiceBindingsClusterRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: meta('%s-servicebindings' % fullname, 'external-secrets', false) {
      labels+: { 'servicebinding.io/controller': 'true' },
    },
    rules: [{ apiGroups: ['external-secrets.io'], resources: ['externalsecrets', 'pushsecrets'], verbs: ['get', 'list', 'watch'] }],
  },

  esLeaderElectionRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'Role',
    metadata: meta('%s-leaderelection' % fullname, 'external-secrets'),
    rules: [
      { apiGroups: [''], resources: ['configmaps'], resourceNames: ['external-secrets-controller'], verbs: ['get', 'update', 'patch'] },
      { apiGroups: [''], resources: ['configmaps'], verbs: ['create'] },
      { apiGroups: ['coordination.k8s.io'], resources: ['leases'], verbs: ['get', 'create', 'update', 'patch'] },
    ],
  },

  esLeaderElectionRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'RoleBinding',
    metadata: meta('%s-leaderelection' % fullname, 'external-secrets'),
    roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'Role', name: '%s-leaderelection' % fullname },
    subjects: [{ kind: 'ServiceAccount', name: fullname, namespace: ns }],
  },

  // --- Webhook ---
  esWebhookServiceAccount: serviceAccount(webhookName, 'external-secrets-webhook'),

  // Filled with the serving certificate by the cert-controller.
  esWebhookSecret: {
    apiVersion: 'v1',
    kind: 'Secret',
    metadata: meta(webhookName, 'external-secrets-webhook') {
      labels+: { 'external-secrets.io/component': 'webhook' },
    },
  },

  esWebhookService: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: meta(webhookName, 'external-secrets-webhook') {
      labels+: { 'external-secrets.io/component': 'webhook' },
    },
    spec: {
      type: 'ClusterIP',
      ports: [{ name: 'webhook', port: 443, targetPort: 10250, protocol: 'TCP' }],
      selector: selector('external-secrets-webhook'),
    },
  },

  esWebhookDeployment: deployment(webhookName, 'external-secrets-webhook', 'webhook', webhookName, {
    containers: [container(
      'webhook',
      'webhook',
      [
        'webhook',
        '--port=10250',
        '--dns-name=%s.%s.svc' % [webhookName, ns],
        '--cert-dir=/tmp/certs',
        '--check-interval=5m',
        '--healthz-addr=:8081',
      ] + common + cfg.extraArgs.webhook,
      readiness {
        ports: [
          { name: 'metrics', containerPort: 8080, protocol: 'TCP' },
          { name: 'webhook', containerPort: 10250, protocol: 'TCP' },
        ],
        volumeMounts: [{ name: 'certs', mountPath: '/tmp/certs', readOnly: true }],
      },
    )],
    volumes: [{ name: 'certs', secret: { secretName: webhookName } }],
  }),

  local webhookConfig(name, rules) = {
    apiVersion: 'admissionregistration.k8s.io/v1',
    kind: 'ValidatingWebhookConfiguration',
    metadata: meta(name, 'external-secrets-webhook', false) {
      labels+: { 'external-secrets.io/component': 'webhook' },
    },
    webhooks: [
      {
        name: 'validate.%s.external-secrets.io' % r.resource,
        rules: [{
          apiGroups: ['external-secrets.io'],
          apiVersions: ['v1'],
          operations: ['CREATE', 'UPDATE', 'DELETE'],
          resources: [r.resource + 's'],
          scope: r.scope,
        }],
        clientConfig: {
          service: {
            namespace: ns,
            name: webhookName,
            path: '/validate-external-secrets-io-v1-%s' % r.resource,
          },
        },
        admissionReviewVersions: ['v1', 'v1beta1'],
        sideEffects: 'None',
        timeoutSeconds: 5,
      } + (if std.objectHas(r, 'failurePolicy') then { failurePolicy: r.failurePolicy } else {})
      for r in rules
    ],
  },

  esSecretStoreWebhook: webhookConfig('secretstore-validate', [
    { resource: 'secretstore', scope: 'Namespaced' },
    { resource: 'clustersecretstore', scope: 'Cluster' },
  ]),

  esExternalSecretWebhook: webhookConfig('externalsecret-validate', [
    { resource: 'externalsecret', scope: 'Namespaced', failurePolicy: 'Fail' },
  ]),

  // --- Cert controller: issues the webhook certificate and injects the CA bundle ---
  esCertControllerServiceAccount: serviceAccount(certName, 'external-secrets-cert-controller'),

  esCertControllerDeployment: deployment(certName, 'external-secrets-cert-controller', 'certController', certName, {
    containers: [container(
      'cert-controller',
      'certController',
      [
        'certcontroller',
        '--crd-requeue-interval=5m',
        '--service-name=' + webhookName,
        '--service-namespace=' + ns,
        '--secret-name=' + webhookName,
        '--secret-namespace=' + ns,
        '--healthz-addr=:8081',
        '--enable-partial-cache=true',
      ] + common + cfg.extraArgs.certController,
      readiness,
    )],
  }),

  esCertControllerClusterRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: meta('%s-cert-controller' % fullname, 'external-secrets-cert-controller', false),
    rules: [
      { apiGroups: ['apiextensions.k8s.io'], resources: ['customresourcedefinitions'], verbs: ['get', 'list', 'watch', 'update', 'patch'] },
      { apiGroups: ['admissionregistration.k8s.io'], resources: ['validatingwebhookconfigurations'], verbs: ['list', 'watch', 'get'] },
      { apiGroups: ['admissionregistration.k8s.io'], resources: ['validatingwebhookconfigurations'], resourceNames: ['secretstore-validate', 'externalsecret-validate'], verbs: ['update', 'patch'] },
      { apiGroups: [''], resources: ['endpoints'], verbs: ['list', 'get', 'watch'] },
      { apiGroups: [''], resources: ['events'], verbs: ['create', 'patch'] },
      { apiGroups: [''], resources: ['secrets'], verbs: ['get', 'list', 'watch', 'update', 'patch'] },
      { apiGroups: ['coordination.k8s.io'], resources: ['leases'], verbs: ['get', 'create', 'update', 'patch'] },
    ],
  },

  esCertControllerClusterRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: meta('%s-cert-controller' % fullname, 'external-secrets-cert-controller', false),
    roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'ClusterRole', name: '%s-cert-controller' % fullname },
    subjects: [{ kind: 'ServiceAccount', name: certName, namespace: ns }],
  },
}
