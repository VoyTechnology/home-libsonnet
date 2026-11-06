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
  local meta(namespace=null) = {
    name: name,
    labels: labels,
  } + (if namespace != null then { namespace: namespace } else {}),

  local get = ['get', 'watch', 'list'],
  local rule(apiGroups, resources, verbs=get) = { apiGroups: apiGroups, resources: resources, verbs: verbs },

  externalDnsNamespace: if cfg.createNamespace then {
    apiVersion: 'v1',
    kind: 'Namespace',
    metadata: { name: ns },
  } else {},

  externalDnsCrds: if cfg.installCRDs then import 'crds/main.libsonnet' else {},

  externalDnsServiceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: meta(ns),
    automountServiceAccountToken: true,
  },

  // Read access to everything the sources can use.
  externalDnsClusterRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: meta(),
    rules: [
      rule([''], ['nodes'], ['list', 'watch']),
      rule([''], ['pods']),
      rule([''], ['services']),
      rule(['discovery.k8s.io'], ['endpointslices']),
      rule(['extensions', 'networking.k8s.io'], ['ingresses']),
      rule(['gateway.networking.k8s.io'], ['gateways']),
      rule([''], ['namespaces']),
      rule(['gateway.networking.k8s.io'], ['httproutes']),
    ],
  },

  externalDnsClusterRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: meta() { name: 'external-dns-viewer' },
    roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'ClusterRole', name: name },
    subjects: [{ kind: 'ServiceAccount', name: name, namespace: ns }],
  },

  externalDnsService: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: meta(ns),
    spec: {
      type: 'ClusterIP',
      ports: [{ name: 'http', port: 7979, targetPort: 'http', protocol: 'TCP' }],
      selector: selector,
    },
  },

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
  externalDnsDeployment: {
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: meta(ns),
    spec: {
      replicas: cfg.replicas,
      strategy: { type: 'Recreate' },
      selector: { matchLabels: selector },
      template: {
        metadata: { labels: selector },
        spec: {
          serviceAccountName: name,
          automountServiceAccountToken: true,
          securityContext: { fsGroup: 65534, runAsNonRoot: true, seccompProfile: { type: 'RuntimeDefault' } },
          containers: [$.external_dns_container],
        } + (if std.length(cfg.nodeSelector) > 0 then { nodeSelector: cfg.nodeSelector } else {})
        + (if std.length(cfg.tolerations) > 0 then { tolerations: cfg.tolerations } else {}),
      },
    },
  },
}
