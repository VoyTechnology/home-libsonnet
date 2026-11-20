local k = import 'k.libsonnet';

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
  local rbac = k.rbac.v1,
  // The labels, and the namespace unless the object is cluster-scoped, for an object of the type `t`.
  local meta(t, component, namespaced=true) =
    t.metadata.withLabels(labels(component))
    + (if namespaced then t.metadata.withNamespace(ns) else {}),
  // Extra labels, e.g. `extraLabels(rbac.clusterRole, { ... })`.
  local extraLabels(t, l) = t.metadata.withLabelsMixin(l),
  local rule(apiGroups, resources, verbs, resourceNames=null) =
    rbac.policyRule.withApiGroups(apiGroups)
    + rbac.policyRule.withResources(resources)
    + rbac.policyRule.withVerbs(verbs)
    + (if resourceNames != null then rbac.policyRule.withResourceNames(resourceNames) else {}),

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

  // `podSpec` is merged into the pod spec; it carries at least the containers.
  local deployment(name, component, key, serviceAccount, podSpec) =
    local d = k.apps.v1.deployment;
    local pod = d.spec.template.spec;
    d.new(name, cfg.replicas[key], podSpec.containers)
    + meta(d, component)
    + d.spec.withRevisionHistoryLimit(10)
    // new() would add a `name` label; the selector is immutable and must stay as it was.
    + d.spec.selector.withMatchLabels(selector(component))
    + d.spec.template.metadata.withLabels(labels(component))
    + pod.withServiceAccountName(serviceAccount)
    + pod.withAutomountServiceAccountToken(true)
    + pod.withHostNetwork(false)
    + { spec+: { template+: { spec+: podSpec } } }
    + (if std.length(cfg.nodeSelector) > 0 then pod.withNodeSelector(cfg.nodeSelector) else {})
    + (if std.length(cfg.tolerations) > 0 then pod.withTolerations(cfg.tolerations) else {}),

  local serviceAccount(name, component) =
    k.core.v1.serviceAccount.new(name) + meta(k.core.v1.serviceAccount, component),

  local common = ['--metrics-addr=:8080', '--loglevel=' + cfg.logLevel, '--zap-time-encoding=epoch'],

  // Empty objects are skipped by Tanka.
  esNamespace: if cfg.createNamespace then
    k.core.v1.namespace.new(ns) + k.core.v1.namespace.metadata.withLabels(labels('external-secrets'))
  else {},

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

  esControllerClusterRole:
    rbac.clusterRole.new('%s-controller' % fullname)
    + meta(rbac.clusterRole, 'external-secrets', false)
    + rbac.clusterRole.withRules([
      rule(
        ['external-secrets.io'],
        ['secretstores', 'clustersecretstores', 'externalsecrets', 'clusterexternalsecrets', 'pushsecrets', 'clusterpushsecrets'],
        ['get', 'list', 'watch'],
      ),
      rule(
        ['external-secrets.io'],
        [
          r + s
          for r in ['externalsecrets', 'secretstores', 'clustersecretstores', 'clusterexternalsecrets', 'pushsecrets', 'clusterpushsecrets']
          for s in ['', '/status', '/finalizers']
        ],
        ['get', 'update', 'patch'],
      ),
      rule(['generators.external-secrets.io'], ['generatorstates'], ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete', 'deletecollection']),
      rule(
        ['generators.external-secrets.io'],
        ['acraccesstokens', 'clustergenerators', 'ecrauthorizationtokens', 'fakes', 'gcraccesstokens', 'githubaccesstokens', 'quayaccesstokens', 'passwords', 'stssessiontokens', 'uuids', 'vaultdynamicsecrets', 'webhooks', 'grafanas', 'mfas'],
        ['get', 'list', 'watch'],
      ),
      rule([''], ['serviceaccounts', 'namespaces'], ['get', 'list', 'watch']),
      rule([''], ['configmaps'], ['get', 'list', 'watch']),
      rule([''], ['secrets'], ['get', 'list', 'watch', 'create', 'update', 'delete', 'patch']),
      rule([''], ['serviceaccounts/token'], ['create']),
      rule([''], ['events'], ['create', 'patch']),
      rule(['external-secrets.io'], ['externalsecrets'], ['create', 'update', 'delete']),
      rule(['external-secrets.io'], ['pushsecrets'], ['create', 'update', 'delete']),
    ]),

  esControllerClusterRoleBinding:
    rbac.clusterRoleBinding.new('%s-controller' % fullname)
    + meta(rbac.clusterRoleBinding, 'external-secrets', false)
    + rbac.clusterRoleBinding.bindRole($.esControllerClusterRole)
    + rbac.clusterRoleBinding.withSubjects([rbac.subject.fromServiceAccount($.esServiceAccount)]),

  local generatorResources = ['acraccesstokens', 'clustergenerators', 'ecrauthorizationtokens', 'fakes', 'gcraccesstokens', 'githubaccesstokens', 'quayaccesstokens', 'passwords', 'vaultdynamicsecrets', 'webhooks', 'grafanas', 'generatorstates', 'mfas'],
  local userResources = ['externalsecrets', 'secretstores', 'clustersecretstores', 'pushsecrets', 'clusterpushsecrets'],

  // Aggregated into the built-in view/edit/admin roles.
  esViewClusterRole:
    rbac.clusterRole.new('%s-view' % fullname)
    + meta(rbac.clusterRole, 'external-secrets', false)
    + extraLabels(rbac.clusterRole, {
      'rbac.authorization.k8s.io/aggregate-to-view': 'true',
      'rbac.authorization.k8s.io/aggregate-to-edit': 'true',
      'rbac.authorization.k8s.io/aggregate-to-admin': 'true',
    })
    + rbac.clusterRole.withRules([
      rule(['external-secrets.io'], userResources, ['get', 'watch', 'list']),
      rule(['generators.external-secrets.io'], generatorResources, ['get', 'watch', 'list']),
    ]),

  esEditClusterRole:
    rbac.clusterRole.new('%s-edit' % fullname)
    + meta(rbac.clusterRole, 'external-secrets', false)
    + extraLabels(rbac.clusterRole, {
      'rbac.authorization.k8s.io/aggregate-to-edit': 'true',
      'rbac.authorization.k8s.io/aggregate-to-admin': 'true',
    })
    + rbac.clusterRole.withRules([
      rule(['external-secrets.io'], userResources, ['create', 'delete', 'deletecollection', 'patch', 'update']),
      rule(['generators.external-secrets.io'], generatorResources, ['create', 'delete', 'deletecollection', 'patch', 'update']),
    ]),

  esServiceBindingsClusterRole:
    rbac.clusterRole.new('%s-servicebindings' % fullname)
    + meta(rbac.clusterRole, 'external-secrets', false)
    + extraLabels(rbac.clusterRole, { 'servicebinding.io/controller': 'true' })
    + rbac.clusterRole.withRules([rule(['external-secrets.io'], ['externalsecrets', 'pushsecrets'], ['get', 'list', 'watch'])]),

  esLeaderElectionRole:
    rbac.role.new('%s-leaderelection' % fullname)
    + meta(rbac.role, 'external-secrets')
    + rbac.role.withRules([
      rule([''], ['configmaps'], ['get', 'update', 'patch'], ['external-secrets-controller']),
      rule([''], ['configmaps'], ['create']),
      rule(['coordination.k8s.io'], ['leases'], ['get', 'create', 'update', 'patch']),
    ]),

  esLeaderElectionRoleBinding:
    rbac.roleBinding.new('%s-leaderelection' % fullname)
    + meta(rbac.roleBinding, 'external-secrets')
    + rbac.roleBinding.bindRole($.esLeaderElectionRole)
    + rbac.roleBinding.withSubjects([rbac.subject.fromServiceAccount($.esServiceAccount)]),

  // --- Webhook ---
  esWebhookServiceAccount: serviceAccount(webhookName, 'external-secrets-webhook'),

  // Filled with the serving certificate by the cert-controller.
  esWebhookSecret:
    k.core.v1.secret.new(webhookName, {})
    + meta(k.core.v1.secret, 'external-secrets-webhook')
    + extraLabels(k.core.v1.secret, { 'external-secrets.io/component': 'webhook' }),

  esWebhookService:
    local svc = k.core.v1.service;
    local port = k.core.v1.servicePort;
    svc.new(webhookName, selector('external-secrets-webhook'), [port.withName('webhook') + port.withPort(443) + port.withTargetPort(10250) + port.withProtocol('TCP')])
    + meta(svc, 'external-secrets-webhook')
    + extraLabels(svc, { 'external-secrets.io/component': 'webhook' })
    + svc.spec.withType('ClusterIP'),

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

  local webhookConfig(name, rules) =
    local w = k.admissionregistration.v1.validatingWebhookConfiguration;
    w.new(name)
    + meta(w, 'external-secrets-webhook', false)
    + extraLabels(w, { 'external-secrets.io/component': 'webhook' })
    + w.withWebhooks(
      [
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
      ]
    ),

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

  esCertControllerClusterRole:
    rbac.clusterRole.new('%s-cert-controller' % fullname)
    + meta(rbac.clusterRole, 'external-secrets-cert-controller', false)
    + rbac.clusterRole.withRules([
      rule(['apiextensions.k8s.io'], ['customresourcedefinitions'], ['get', 'list', 'watch', 'update', 'patch']),
      rule(['admissionregistration.k8s.io'], ['validatingwebhookconfigurations'], ['list', 'watch', 'get']),
      rule(['admissionregistration.k8s.io'], ['validatingwebhookconfigurations'], ['update', 'patch'], ['secretstore-validate', 'externalsecret-validate']),
      rule([''], ['endpoints'], ['list', 'get', 'watch']),
      rule([''], ['events'], ['create', 'patch']),
      rule([''], ['secrets'], ['get', 'list', 'watch', 'update', 'patch']),
      rule(['coordination.k8s.io'], ['leases'], ['get', 'create', 'update', 'patch']),
    ]),

  esCertControllerClusterRoleBinding:
    rbac.clusterRoleBinding.new('%s-cert-controller' % fullname)
    + meta(rbac.clusterRoleBinding, 'external-secrets-cert-controller', false)
    + rbac.clusterRoleBinding.bindRole($.esCertControllerClusterRole)
    + rbac.clusterRoleBinding.withSubjects([rbac.subject.fromServiceAccount($.esCertControllerServiceAccount)]),
}
