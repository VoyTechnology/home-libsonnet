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

  envoyGatewayNamespace: if cfg.createNamespace then {
    apiVersion: 'v1',
    kind: 'Namespace',
    metadata: { name: ns },
  } else {},

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

  envoyGatewayServiceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      name: 'envoy-gateway',
      namespace: ns,
      labels: labels,
    },
  },

  envoyGatewayConfigMap: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: {
      name: 'envoy-gateway-config',
      namespace: ns,
      labels: labels,
    },
    data: {
      'envoy-gateway.yaml': std.manifestYamlDoc($.envoy_gateway_config, quote_keys=false),
    },
  },

  envoyGatewayClusterRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: {
      creationTimestamp: null,
      name: 'envoy-gateway-helm-envoy-gateway-role',
      labels: labels,
    },
    rules: [
      {
        apiGroups: [''],
        resources: ['nodes', 'namespaces'],
        verbs: ['get', 'list', 'watch'],
      },
      {
        apiGroups: ['gateway.networking.k8s.io'],
        resources: ['gatewayclasses'],
        verbs: ['get', 'list', 'patch', 'update', 'watch'],
      },
      {
        apiGroups: ['gateway.networking.k8s.io'],
        resources: ['gatewayclasses/status'],
        verbs: ['update'],
      },
      {
        apiGroups: ['multicluster.x-k8s.io'],
        resources: ['serviceimports'],
        verbs: ['get', 'list', 'watch'],
      },
      {
        apiGroups: [''],
        resources: ['configmaps', 'secrets', 'services'],
        verbs: ['get', 'list', 'watch'],
      },
      {
        apiGroups: ['apps'],
        resources: ['deployments', 'daemonsets'],
        verbs: ['get', 'list', 'watch'],
      },
      {
        apiGroups: ['discovery.k8s.io'],
        resources: ['endpointslices'],
        verbs: ['get', 'list', 'watch'],
      },
      {
        apiGroups: ['gateway.envoyproxy.io'],
        resources: [
          'envoyproxies',
          'envoypatchpolicies',
          'clienttrafficpolicies',
          'backendtrafficpolicies',
          'securitypolicies',
          'envoyextensionpolicies',
          'backends',
          'httproutefilters',
        ],
        verbs: ['get', 'list', 'watch'],
      },
      {
        apiGroups: ['gateway.envoyproxy.io'],
        resources: [
          'envoypatchpolicies/status',
          'clienttrafficpolicies/status',
          'backendtrafficpolicies/status',
          'securitypolicies/status',
          'envoyextensionpolicies/status',
          'backends/status',
        ],
        verbs: ['update'],
      },
      {
        apiGroups: ['gateway.networking.k8s.io'],
        resources: [
          'gateways',
          'grpcroutes',
          'httproutes',
          'referencegrants',
          'tcproutes',
          'tlsroutes',
          'udproutes',
          'backendtlspolicies',
        ],
        verbs: ['get', 'list', 'watch'],
      },
      {
        apiGroups: ['gateway.networking.k8s.io'],
        resources: [
          'gateways/status',
          'grpcroutes/status',
          'httproutes/status',
          'tcproutes/status',
          'tlsroutes/status',
          'udproutes/status',
          'backendtlspolicies/status',
        ],
        verbs: ['update'],
      },
      {
        apiGroups: ['gateway.networking.x-k8s.io'],
        resources: ['xlistenersets'],
        verbs: ['get', 'list', 'watch'],
      },
      {
        apiGroups: ['gateway.networking.x-k8s.io'],
        resources: ['xlistenersets/status'],
        verbs: ['update'],
      },
      {
        apiGroups: [''],
        resources: ['pods', 'pods/binding'],
        verbs: ['get', 'list', 'patch', 'update', 'watch'],
      },
    ],
  },

  envoyGatewayClusterRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: {
      name: 'envoy-gateway-helm-envoy-gateway-rolebinding',
      labels: labels,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: 'envoy-gateway-helm-envoy-gateway-role',
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: 'envoy-gateway',
        namespace: ns,
      },
    ],
  },

  envoyGatewayInfraManagerRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'Role',
    metadata: {
      name: 'envoy-gateway-helm-infra-manager',
      namespace: ns,
      labels: labels,
    },
    rules: [
      {
        apiGroups: [''],
        resources: ['serviceaccounts', 'services', 'configmaps'],
        verbs: ['create', 'get', 'list', 'delete', 'deletecollection', 'patch'],
      },
      {
        apiGroups: ['apps'],
        resources: ['deployments', 'daemonsets'],
        verbs: ['create', 'get', 'delete', 'deletecollection', 'patch'],
      },
      {
        apiGroups: ['autoscaling', 'policy'],
        resources: ['horizontalpodautoscalers', 'poddisruptionbudgets'],
        verbs: ['create', 'get', 'list', 'delete', 'deletecollection', 'patch'],
      },
      {
        apiGroups: ['certificates.k8s.io'],
        resources: ['clustertrustbundles'],
        verbs: ['list', 'get', 'watch'],
      },
    ],
  },

  envoyGatewayLeaderElectionRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'Role',
    metadata: {
      name: 'envoy-gateway-helm-leader-election-role',
      namespace: ns,
      labels: labels,
    },
    rules: [
      {
        apiGroups: [''],
        resources: ['configmaps'],
        verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'],
      },
      {
        apiGroups: ['coordination.k8s.io'],
        resources: ['leases'],
        verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'],
      },
      {
        apiGroups: [''],
        resources: ['events'],
        verbs: ['create', 'patch'],
      },
    ],
  },

  envoyGatewayInfraManagerRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'RoleBinding',
    metadata: {
      name: 'envoy-gateway-helm-infra-manager',
      namespace: ns,
      labels: labels,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'Role',
      name: 'envoy-gateway-helm-infra-manager',
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: 'envoy-gateway',
        namespace: ns,
      },
    ],
  },

  envoyGatewayLeaderElectionRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'RoleBinding',
    metadata: {
      name: 'envoy-gateway-helm-leader-election-rolebinding',
      namespace: ns,
      labels: labels,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'Role',
      name: 'envoy-gateway-helm-leader-election-role',
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: 'envoy-gateway',
        namespace: ns,
      },
    ],
  },

  envoyGatewayService: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: 'envoy-gateway',
      namespace: ns,
      labels: labels {
        'control-plane': 'envoy-gateway',
      },
    },
    spec: {
      type: 'ClusterIP',
      selector: {
        'control-plane': 'envoy-gateway',
        'app.kubernetes.io/name': 'gateway-helm',
        'app.kubernetes.io/instance': 'envoy',
      },
      ports: [
        {
          name: 'grpc',
          port: 18000,
          targetPort: 18000,
        },
        {
          name: 'ratelimit',
          port: 18001,
          targetPort: 18001,
        },
        {
          name: 'wasm',
          port: 18002,
          targetPort: 18002,
        },
        {
          name: 'metrics',
          port: 19001,
          targetPort: 19001,
        },
        {
          name: 'webhook',
          port: 9443,
          targetPort: 9443,
        },
      ],
    },
  },

  envoyGatewayDeployment: {
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: {
      name: 'envoy-gateway',
      namespace: ns,
      labels: labels {
        'control-plane': 'envoy-gateway',
      },
    },
    spec: {
      replicas: 1,
      selector: {
        matchLabels: {
          'control-plane': 'envoy-gateway',
          'app.kubernetes.io/name': 'gateway-helm',
          'app.kubernetes.io/instance': 'envoy',
        },
      },
      template: {
        metadata: {
          annotations: {
            'prometheus.io/port': '19001',
            'prometheus.io/scrape': 'true',
          },
          labels: {
            'control-plane': 'envoy-gateway',
            'app.kubernetes.io/name': 'gateway-helm',
            'app.kubernetes.io/instance': 'envoy',
          },
        },
        spec: {
          containers: [
            $.envoy_gateway_container,
          ],
          imagePullSecrets: [],
          serviceAccountName: 'envoy-gateway',
          terminationGracePeriodSeconds: 10,
          volumes: [
            {
              configMap: {
                defaultMode: 420,
                name: 'envoy-gateway-config',
              },
              name: 'envoy-gateway-config',
            },
            {
              name: 'certs',
              secret: {
                secretName: 'envoy-gateway',
              },
            },
          ],
        },
      },
    },
  },

  envoyGatewayTopologyWebhook: {
    apiVersion: 'admissionregistration.k8s.io/v1',
    kind: 'MutatingWebhookConfiguration',
    metadata: {
      name: 'envoy-gateway-topology-injector.' + ns,
      labels: labels {
        'app.kubernetes.io/component': 'topology-injector',
      },
    },
    webhooks: [
      {
        name: 'topology.webhook.gateway.envoyproxy.io',
        admissionReviewVersions: ['v1'],
        sideEffects: 'None',
        clientConfig: {
          service: {
            name: 'envoy-gateway',
            namespace: ns,
            path: '/inject-pod-topology',
            port: 9443,
          },
        },
        failurePolicy: 'Ignore',
        rules: [
          {
            operations: ['CREATE'],
            apiGroups: [''],
            apiVersions: ['v1'],
            resources: ['pods/binding'],
          },
        ],
        namespaceSelector: {
          matchExpressions: [
            {
              key: 'kubernetes.io/metadata.name',
              operator: 'In',
              values: [
                ns,
              ],
            },
          ],
        },
      },
    ],
  },

  // One-off Job generating the control plane TLS Secrets (the chart runs it as a pre-install hook).
  envoyGatewayCertgen: if cfg.certgen then {
    serviceAccount: {
      apiVersion: 'v1',
      kind: 'ServiceAccount',
      metadata: {
        name: 'envoy-gateway-helm-certgen',
        namespace: ns,
        labels: labels,
      },
    },
    clusterRole: {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'ClusterRole',
      metadata: {
        name: 'envoy-gateway-helm-certgen:' + ns,
        labels: labels,
      },
      rules: [
        {
          apiGroups: ['admissionregistration.k8s.io'],
          resources: ['mutatingwebhookconfigurations'],
          verbs: ['get', 'list', 'watch'],
        },
        {
          apiGroups: ['admissionregistration.k8s.io'],
          resources: ['mutatingwebhookconfigurations'],
          resourceNames: [
            'envoy-gateway-topology-injector.' + ns,
          ],
          verbs: ['update', 'patch'],
        },
      ],
    },
    clusterRoleBinding: {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'ClusterRoleBinding',
      metadata: {
        name: 'envoy-gateway-helm-certgen:' + ns,
        labels: labels,
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'ClusterRole',
        name: 'envoy-gateway-helm-certgen:' + ns,
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: 'envoy-gateway-helm-certgen',
          namespace: ns,
        },
      ],
    },
    role: {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'Role',
      metadata: {
        name: 'envoy-gateway-helm-certgen',
        namespace: ns,
        labels: labels,
      },
      rules: [
        {
          apiGroups: [''],
          resources: ['secrets'],
          verbs: ['get', 'create', 'update'],
        },
      ],
    },
    roleBinding: {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'RoleBinding',
      metadata: {
        name: 'envoy-gateway-helm-certgen',
        namespace: ns,
        labels: labels,
      },
      roleRef: {
        apiGroup: 'rbac.authorization.k8s.io',
        kind: 'Role',
        name: 'envoy-gateway-helm-certgen',
      },
      subjects: [
        {
          kind: 'ServiceAccount',
          name: 'envoy-gateway-helm-certgen',
          namespace: ns,
        },
      ],
    },
    job: {
      apiVersion: 'batch/v1',
      kind: 'Job',
      metadata: {
        name: 'envoy-gateway-helm-certgen',
        namespace: ns,
        labels: labels,
      },
      spec: {
        backoffLimit: 1,
        completions: 1,
        parallelism: 1,
        template: {
          metadata: {
            labels: {
              app: 'certgen',
            },
          },
          spec: {
            containers: [
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
            ],
            imagePullSecrets: [],
            restartPolicy: 'Never',
            serviceAccountName: 'envoy-gateway-helm-certgen',
          },
        },
        ttlSecondsAfterFinished: 30,
      },
    },
  } else {},
}
