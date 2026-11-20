local k = import 'k.libsonnet';

// Envoy Gateway, modelled on the upstream gateway-helm chart's rendering (v1.7.0, release name
// `envoy`): the control plane Deployment, Service, RBAC, topology webhook and the Envoy CRDs (see
// generate.sh). Names, selectors and labels are the chart's, so it can take over from a Helm install
// in place. The Gateway API CRDs are not included: k3s ships them (traefik-crd).
{
  local cfg = $._config,
  local ns = cfg.namespace,
  // Selectors are immutable. Never change the labels used in them.
  local labels = {
    'app.kubernetes.io/name': 'gateway-helm',
    'app.kubernetes.io/instance': 'envoy',
    'app.kubernetes.io/version': std.lstripChars(std.reverse(std.split($._images.gateway, ':'))[0], 'v'),
    'app.kubernetes.io/managed-by': 'Tanka',
  },

  local rbac = k.rbac.v1,
  // The labels, and the namespace unless the object is cluster-scoped, for an object of the type `t`.
  local meta(t, namespaced=true) =
    t.metadata.withLabels(labels) + (if namespaced then t.metadata.withNamespace(ns) else {}),
  local rule(apiGroups, resources, verbs, resourceNames=null) =
    rbac.policyRule.withApiGroups(apiGroups)
    + rbac.policyRule.withResources(resources)
    + rbac.policyRule.withVerbs(verbs)
    + (if resourceNames != null then rbac.policyRule.withResourceNames(resourceNames) else {}),
  // Immutable selector of the control plane pods.
  local selector = {
    'control-plane': 'envoy-gateway',
    'app.kubernetes.io/name': 'gateway-helm',
    'app.kubernetes.io/instance': 'envoy',
  },

  envoyGatewayNamespace: if cfg.createNamespace then k.core.v1.namespace.new(ns) else {},

  envoyGatewayCrds: if cfg.installCRDs then import 'crds/main.libsonnet' else {},

  envoy_gateway_container:: {
    args: [
      'server',
      '--config-path=/config/envoy-gateway.yaml',
    ],
    env: [
      {
        name: 'ENVOY_GATEWAY_NAMESPACE',
        valueFrom: {
          fieldRef: {
            apiVersion: 'v1',
            fieldPath: 'metadata.namespace',
          },
        },
      },
      {
        name: 'KUBERNETES_CLUSTER_DOMAIN',
        value: 'cluster.local',
      },
    ],
    image: $._images.gateway,
    imagePullPolicy: 'IfNotPresent',
    livenessProbe: {
      httpGet: {
        path: '/healthz',
        port: 8081,
      },
      initialDelaySeconds: 15,
      periodSeconds: 20,
    },
    name: 'envoy-gateway',
    ports: [
      {
        containerPort: 18000,
        name: 'grpc',
      },
      {
        containerPort: 18001,
        name: 'ratelimit',
      },
      {
        containerPort: 18002,
        name: 'wasm',
      },
      {
        containerPort: 19001,
        name: 'metrics',
      },
      {
        name: 'webhook',
        containerPort: 9443,
      },
    ],
    readinessProbe: {
      httpGet: {
        path: '/readyz',
        port: 8081,
      },
      initialDelaySeconds: 5,
      periodSeconds: 10,
    },
    resources: {
      limits: {
        memory: '1024Mi',
      },
      requests: {
        cpu: '100m',
        memory: '256Mi',
      },
    },
    securityContext: {
      allowPrivilegeEscalation: false,
      capabilities: {
        drop: ['ALL'],
      },
      privileged: false,
      runAsGroup: 65532,
      runAsNonRoot: true,
      runAsUser: 65532,
      seccompProfile: {
        type: 'RuntimeDefault',
      },
    },
    volumeMounts: [
      {
        mountPath: '/config',
        name: 'envoy-gateway-config',
        readOnly: true,
      },
      {
        mountPath: '/certs',
        name: 'certs',
        readOnly: true,
      },
    ],
  },

  // The EnvoyGateway configuration. Extend it with a mixin, e.g. `envoy_gateway_config+:: { gatewayAPI: { enabled: ['XListenerSet'] } }`.
  envoy_gateway_config:: {
    apiVersion: 'gateway.envoyproxy.io/v1alpha1',
    kind: 'EnvoyGateway',
    extensionApis: {},
    gateway: {
      controllerName: 'gateway.envoyproxy.io/gatewayclass-controller',
    },
    logging: {
      level: {
        default: 'info',
      },
    },
    provider: {
      kubernetes: {
        rateLimitDeployment: {
          container: {
            image: $._images.ratelimit,
          },
          patch: {
            type: 'StrategicMerge',
            value: {
              spec: {
                template: {
                  spec: {
                    containers: [
                      {
                        imagePullPolicy: 'IfNotPresent',
                        name: 'envoy-ratelimit',
                      },
                    ],
                  },
                },
              },
            },
          },
        },
        shutdownManager: {
          image: $._images.gateway,
        },
      },
      type: 'Kubernetes',
    },
  },

  envoyGatewayServiceAccount: k.core.v1.serviceAccount.new('envoy-gateway') + meta(k.core.v1.serviceAccount),

  envoyGatewayConfigMap:
    k.core.v1.configMap.new('envoy-gateway-config', {
      'envoy-gateway.yaml': std.manifestYamlDoc($.envoy_gateway_config, quote_keys=false),
    })
    + meta(k.core.v1.configMap),

  envoyGatewayClusterRole:
    rbac.clusterRole.new('envoy-gateway-helm-envoy-gateway-role')
    + meta(rbac.clusterRole, false)
    // The chart renders an explicit null here.
    + { metadata+: { creationTimestamp: null } }
    + rbac.clusterRole.withRules([
      rule([''], ['nodes', 'namespaces'], ['get', 'list', 'watch']),
      rule(['gateway.networking.k8s.io'], ['gatewayclasses'], ['get', 'list', 'patch', 'update', 'watch']),
      rule(['gateway.networking.k8s.io'], ['gatewayclasses/status'], ['update']),
      rule(['multicluster.x-k8s.io'], ['serviceimports'], ['get', 'list', 'watch']),
      rule([''], ['configmaps', 'secrets', 'services'], ['get', 'list', 'watch']),
      rule(['apps'], ['deployments', 'daemonsets'], ['get', 'list', 'watch']),
      rule(['discovery.k8s.io'], ['endpointslices'], ['get', 'list', 'watch']),
      rule(['gateway.envoyproxy.io'], ['envoyproxies', 'envoypatchpolicies', 'clienttrafficpolicies', 'backendtrafficpolicies', 'securitypolicies', 'envoyextensionpolicies', 'backends', 'httproutefilters'], ['get', 'list', 'watch']),
      rule(['gateway.envoyproxy.io'], ['envoypatchpolicies/status', 'clienttrafficpolicies/status', 'backendtrafficpolicies/status', 'securitypolicies/status', 'envoyextensionpolicies/status', 'backends/status'], ['update']),
      rule(['gateway.networking.k8s.io'], ['gateways', 'grpcroutes', 'httproutes', 'referencegrants', 'tcproutes', 'tlsroutes', 'udproutes', 'backendtlspolicies'], ['get', 'list', 'watch']),
      rule(['gateway.networking.k8s.io'], ['gateways/status', 'grpcroutes/status', 'httproutes/status', 'tcproutes/status', 'tlsroutes/status', 'udproutes/status', 'backendtlspolicies/status'], ['update']),
      rule(['gateway.networking.x-k8s.io'], ['xlistenersets'], ['get', 'list', 'watch']),
      rule(['gateway.networking.x-k8s.io'], ['xlistenersets/status'], ['update']),
      rule([''], ['pods', 'pods/binding'], ['get', 'list', 'patch', 'update', 'watch']),
    ]),

  envoyGatewayClusterRoleBinding:
    rbac.clusterRoleBinding.new('envoy-gateway-helm-envoy-gateway-rolebinding')
    + meta(rbac.clusterRoleBinding, false)
    + rbac.clusterRoleBinding.bindRole($.envoyGatewayClusterRole)
    + rbac.clusterRoleBinding.withSubjects([rbac.subject.fromServiceAccount($.envoyGatewayServiceAccount)]),

  envoyGatewayInfraManagerRole:
    rbac.role.new('envoy-gateway-helm-infra-manager')
    + meta(rbac.role)
    + rbac.role.withRules([
      rule([''], ['serviceaccounts', 'services', 'configmaps'], ['create', 'get', 'list', 'delete', 'deletecollection', 'patch']),
      rule(['apps'], ['deployments', 'daemonsets'], ['create', 'get', 'delete', 'deletecollection', 'patch']),
      rule(['autoscaling', 'policy'], ['horizontalpodautoscalers', 'poddisruptionbudgets'], ['create', 'get', 'list', 'delete', 'deletecollection', 'patch']),
      rule(['certificates.k8s.io'], ['clustertrustbundles'], ['list', 'get', 'watch']),
    ]),

  envoyGatewayLeaderElectionRole:
    rbac.role.new('envoy-gateway-helm-leader-election-role')
    + meta(rbac.role)
    + rbac.role.withRules([
      rule([''], ['configmaps'], ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete']),
      rule(['coordination.k8s.io'], ['leases'], ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete']),
      rule([''], ['events'], ['create', 'patch']),
    ]),

  envoyGatewayInfraManagerRoleBinding:
    rbac.roleBinding.new('envoy-gateway-helm-infra-manager')
    + meta(rbac.roleBinding)
    + rbac.roleBinding.bindRole($.envoyGatewayInfraManagerRole)
    + rbac.roleBinding.withSubjects([rbac.subject.fromServiceAccount($.envoyGatewayServiceAccount)]),

  envoyGatewayLeaderElectionRoleBinding:
    rbac.roleBinding.new('envoy-gateway-helm-leader-election-rolebinding')
    + meta(rbac.roleBinding)
    + rbac.roleBinding.bindRole($.envoyGatewayLeaderElectionRole)
    + rbac.roleBinding.withSubjects([rbac.subject.fromServiceAccount($.envoyGatewayServiceAccount)]),

  envoyGatewayService:
    local svc = k.core.v1.service;
    local port(n, p) = k.core.v1.servicePort.withName(n) + k.core.v1.servicePort.withPort(p) + k.core.v1.servicePort.withTargetPort(p);
    svc.new('envoy-gateway', selector, [
      port('grpc', 18000),
      port('ratelimit', 18001),
      port('wasm', 18002),
      port('metrics', 19001),
      port('webhook', 9443),
    ])
    + meta(svc)
    + svc.metadata.withLabelsMixin({ 'control-plane': 'envoy-gateway' })
    + svc.spec.withType('ClusterIP'),

  envoyGatewayDeployment:
    local d = k.apps.v1.deployment;
    local pod = d.spec.template.spec;
    d.new('envoy-gateway', 1, [$.envoy_gateway_container])
    + meta(d)
    + d.metadata.withLabelsMixin({ 'control-plane': 'envoy-gateway' })
    // new() would add a `name` label; the selector is immutable and must stay as it was.
    + d.spec.selector.withMatchLabels(selector)
    + d.spec.template.metadata.withLabels(selector)
    + d.spec.template.metadata.withAnnotations({ 'prometheus.io/port': '19001', 'prometheus.io/scrape': 'true' })
    + pod.withImagePullSecrets([])
    + pod.withServiceAccountName('envoy-gateway')
    + pod.withTerminationGracePeriodSeconds(10)
    + pod.withVolumes([
      { name: 'envoy-gateway-config', configMap: { name: 'envoy-gateway-config', defaultMode: 420 } },
      { name: 'certs', secret: { secretName: 'envoy-gateway' } },
    ]),

  envoyGatewayTopologyWebhook:
    local w = k.admissionregistration.v1.mutatingWebhookConfiguration;
    w.new('envoy-gateway-topology-injector.' + ns)
    + meta(w, false)
    + w.metadata.withLabelsMixin({ 'app.kubernetes.io/component': 'topology-injector' })
    + w.withWebhooks([{
      name: 'topology.webhook.gateway.envoyproxy.io',
      admissionReviewVersions: ['v1'],
      sideEffects: 'None',
      clientConfig: { service: { name: 'envoy-gateway', namespace: ns, path: '/inject-pod-topology', port: 9443 } },
      failurePolicy: 'Ignore',
      rules: [{ operations: ['CREATE'], apiGroups: [''], apiVersions: ['v1'], resources: ['pods/binding'] }],
      namespaceSelector: { matchExpressions: [{ key: 'kubernetes.io/metadata.name', operator: 'In', values: [ns] }] },
    }]),

  // One-off Job generating the control plane TLS Secrets (the chart runs it as a pre-install hook).
  envoyGatewayCertgen: if cfg.certgen then {
    serviceAccount: k.core.v1.serviceAccount.new('envoy-gateway-helm-certgen') + meta(k.core.v1.serviceAccount),
    clusterRole:
      rbac.clusterRole.new('envoy-gateway-helm-certgen:' + ns)
      + meta(rbac.clusterRole, false)
      + rbac.clusterRole.withRules([
        rule(['admissionregistration.k8s.io'], ['mutatingwebhookconfigurations'], ['get', 'list', 'watch']),
        rule(['admissionregistration.k8s.io'], ['mutatingwebhookconfigurations'], ['update', 'patch'], ['envoy-gateway-topology-injector.' + ns]),
      ]),
    clusterRoleBinding:
      rbac.clusterRoleBinding.new('envoy-gateway-helm-certgen:' + ns)
      + meta(rbac.clusterRoleBinding, false)
      + rbac.clusterRoleBinding.bindRole($.envoyGatewayCertgen.clusterRole)
      + rbac.clusterRoleBinding.withSubjects([rbac.subject.fromServiceAccount($.envoyGatewayCertgen.serviceAccount)]),
    role:
      rbac.role.new('envoy-gateway-helm-certgen')
      + meta(rbac.role)
      + rbac.role.withRules([
        rule([''], ['secrets'], ['get', 'create', 'update']),
      ]),
    roleBinding:
      rbac.roleBinding.new('envoy-gateway-helm-certgen')
      + meta(rbac.roleBinding)
      + rbac.roleBinding.bindRole($.envoyGatewayCertgen.role)
      + rbac.roleBinding.withSubjects([rbac.subject.fromServiceAccount($.envoyGatewayCertgen.serviceAccount)]),
    job:
      local job = k.batch.v1.job;
      job.new('envoy-gateway-helm-certgen')
      + meta(job)
      + job.spec.withBackoffLimit(1)
      + job.spec.withCompletions(1)
      + job.spec.withParallelism(1)
      + job.spec.withTtlSecondsAfterFinished(30)
      + job.spec.template.metadata.withLabels({ app: 'certgen' })
      + job.spec.template.spec.withContainers([
        {
          command: ['envoy-gateway', 'certgen'],
          env: [
            {
              name: 'ENVOY_GATEWAY_NAMESPACE',
              valueFrom: {
                fieldRef: {
                  apiVersion: 'v1',
                  fieldPath: 'metadata.namespace',
                },
              },
            },
            {
              name: 'KUBERNETES_CLUSTER_DOMAIN',
              value: 'cluster.local',
            },
          ],
          image: $._images.gateway,
          imagePullPolicy: 'IfNotPresent',
          name: 'envoy-gateway-certgen',
          securityContext: {
            allowPrivilegeEscalation: false,
            capabilities: {
              drop: ['ALL'],
            },
            privileged: false,
            readOnlyRootFilesystem: true,
            runAsGroup: 65532,
            runAsNonRoot: true,
            runAsUser: 65532,
            seccompProfile: {
              type: 'RuntimeDefault',
            },
          },
        },
      ])
      + job.spec.template.spec.withImagePullSecrets([])
      + job.spec.template.spec.withRestartPolicy('Never')
      + job.spec.template.spec.withServiceAccountName('envoy-gateway-helm-certgen'),
  } else {},
}
