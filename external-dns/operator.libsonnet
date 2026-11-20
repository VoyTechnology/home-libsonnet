local k = import 'k.libsonnet';

// external-dns, modelled on the upstream Helm chart's rendering: a Deployment with its
// ServiceAccount, ClusterRole and binding, Service and the vendored CRDs (see generate.sh).
// Object names are the chart's, so it can replace a Helm install in place.
{
  local cfg = $._config,
  local ns = cfg.namespace,
  local name = 'external-dns',
  // The image tag is the version.
  local version = std.reverse(std.split($._images.externalDns, ':'))[0],

  // Selectors are immutable. Never change these.
  local selector = {
    'app.kubernetes.io/name': name,
    'app.kubernetes.io/instance': name,
  },
  // Metadata labels, free to change.
  local labels = selector {
    'app.kubernetes.io/version': std.lstripChars(version, 'v'),
    'app.kubernetes.io/managed-by': 'Tanka',
  },
  // The labels, and the namespace unless the object is cluster-scoped, for an object of the type `t`.
  local meta(t, namespaced=true) =
    t.metadata.withLabels(labels)
    + (if namespaced then t.metadata.withNamespace(ns) else {}),

  local get = ['get', 'watch', 'list'],
  local rule(apiGroups, resources, verbs=get) =
    k.rbac.v1.policyRule.withApiGroups(apiGroups)
    + k.rbac.v1.policyRule.withResources(resources)
    + k.rbac.v1.policyRule.withVerbs(verbs),

  externalDnsNamespace: if cfg.createNamespace then k.core.v1.namespace.new(ns) else {},

  externalDnsCrds: if cfg.installCRDs then import 'crds/main.libsonnet' else {},

  externalDnsServiceAccount:
    k.core.v1.serviceAccount.new(name)
    + meta(k.core.v1.serviceAccount)
    + k.core.v1.serviceAccount.withAutomountServiceAccountToken(true),

  // Read access to everything the sources can use.
  externalDnsClusterRole:
    k.rbac.v1.clusterRole.new(name)
    + meta(k.rbac.v1.clusterRole, false)
    + k.rbac.v1.clusterRole.withRules([
      rule([''], ['nodes'], ['list', 'watch']),
      rule([''], ['pods']),
      rule([''], ['services']),
      rule(['discovery.k8s.io'], ['endpointslices']),
      rule(['extensions', 'networking.k8s.io'], ['ingresses']),
      rule(['gateway.networking.k8s.io'], ['gateways']),
      rule([''], ['namespaces']),
      rule(['gateway.networking.k8s.io'], ['httproutes']),
    ]),

  externalDnsClusterRoleBinding:
    k.rbac.v1.clusterRoleBinding.new('external-dns-viewer')
    + meta(k.rbac.v1.clusterRoleBinding, false)
    + k.rbac.v1.clusterRoleBinding.bindRole($.externalDnsClusterRole)
    + k.rbac.v1.clusterRoleBinding.withSubjects([k.rbac.v1.subject.fromServiceAccount($.externalDnsServiceAccount)]),

  externalDnsService:
    local svc = k.core.v1.service;
    local port = k.core.v1.servicePort;
    svc.new(name, selector, [port.withName('http') + port.withPort(7979) + port.withTargetPort('http') + port.withProtocol('TCP')])
    + meta(svc)
    + svc.spec.withType('ClusterIP'),

  // The container. Extend it with a mixin, e.g. `external_dns_container+:: { args+: ['--txt-owner-id=bet1'] }`.
  external_dns_container:: {
    local probe(initialDelaySeconds, failureThreshold) = {
      httpGet: { path: '/healthz', port: 'http' },
      initialDelaySeconds: initialDelaySeconds,
      periodSeconds: 10,
      timeoutSeconds: 5,
      successThreshold: 1,
      failureThreshold: failureThreshold,
    },
    name: name,
    image: $._images.externalDns,
    imagePullPolicy: 'IfNotPresent',
    args: [
            '--log-level=info',
            '--log-format=text',
            '--interval=' + cfg.interval,
          ] + ['--source=' + s for s in cfg.sources] + [
            '--policy=' + cfg.policy,
            '--registry=' + cfg.registry,
            '--provider=' + cfg.provider,
          ] + (if cfg.annotationFilter != '' then ['--annotation-filter=' + cfg.annotationFilter] else [])
          + cfg.extraArgs,
    env: cfg.env,
    ports: [{ name: 'http', containerPort: 7979, protocol: 'TCP' }],
    livenessProbe: probe(10, 2),
    readinessProbe: probe(5, 6),
    securityContext: {
      allowPrivilegeEscalation: false,
      capabilities: { drop: ['ALL'] },
      privileged: false,
      readOnlyRootFilesystem: true,
      runAsGroup: 65532,
      runAsNonRoot: true,
      runAsUser: 65532,
    },
  } + (if std.length(cfg.resources) > 0 then { resources: cfg.resources } else {}),

  // Recreate: two instances writing the same records would fight.
  externalDnsDeployment:
    local d = k.apps.v1.deployment;
    local pod = d.spec.template.spec;
    d.new(name, cfg.replicas, [$.external_dns_container])
    + meta(d)
    // new() would add a `name` label; the selector is immutable and must stay as it was.
    + d.spec.selector.withMatchLabels(selector)
    + d.spec.template.metadata.withLabels(selector)
    + d.spec.strategy.withType('Recreate')
    + pod.withServiceAccountName(name)
    + pod.withAutomountServiceAccountToken(true)
    + pod.securityContext.withFsGroup(65534)
    + pod.securityContext.withRunAsNonRoot(true)
    + pod.securityContext.seccompProfile.withType('RuntimeDefault')
    + (if std.length(cfg.nodeSelector) > 0 then pod.withNodeSelector(cfg.nodeSelector) else {})
    + (if std.length(cfg.tolerations) > 0 then pod.withTolerations(cfg.tolerations) else {}),
}
