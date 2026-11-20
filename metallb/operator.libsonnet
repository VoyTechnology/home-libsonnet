local k = import 'k.libsonnet';

// MetalLB, modelled on the upstream Helm chart's rendering (chart 0.15.2): controller Deployment,
// speaker DaemonSet (with the FRR sidecars the chart ships), RBAC, webhook and the vendored CRDs
// (see generate.sh). Object names, labels and selectors are the chart's, so it can take over from
// a Helm install in place.
{
  local cfg = $._config,
  local ns = cfg.namespace,
  // Selectors are immutable. Never change the ones below.
  local labels = {
    'app.kubernetes.io/name': 'metallb',
    'app.kubernetes.io/instance': 'metallb',
    'app.kubernetes.io/version': std.lstripChars(std.reverse(std.split($._images.controller, ':'))[0], 'v'),
    'app.kubernetes.io/managed-by': 'Tanka',
  },

  local rbac = k.rbac.v1,
  // Labels of the pods of a component; also the pod selector, which is immutable.
  local selector(component) = {
    'app.kubernetes.io/name': 'metallb',
    'app.kubernetes.io/instance': 'metallb',
    'app.kubernetes.io/component': component,
  },
  // The labels (and the component, if any), and the namespace unless the object is cluster-scoped,
  // for an object of the type `t`.
  local meta(t, component=null, namespaced=true) =
    t.metadata.withLabels(labels)
    + (if component != null then t.metadata.withLabelsMixin({ 'app.kubernetes.io/component': component }) else {})
    + (if namespaced then t.metadata.withNamespace(ns) else {}),
  local rule(apiGroups, resources, verbs, resourceNames=null) =
    rbac.policyRule.withApiGroups(apiGroups)
    + rbac.policyRule.withResources(resources)
    + rbac.policyRule.withVerbs(verbs)
    + (if resourceNames != null then rbac.policyRule.withResourceNames(resourceNames) else {}),

  metallbNamespace: if cfg.createNamespace then k.core.v1.namespace.new(ns) else {},

  metallbCrds: if cfg.installCRDs then import 'crds/main.libsonnet' else {},

  // The containers. Extend them with a mixin, e.g. `metallb_speaker_container+:: { args+: ['--log-level=debug'] }`.
  metallb_controller_container:: {
    name: 'controller',
    image: $._images.controller,
    args: ['--port=7472', '--log-level=info', '--tls-min-version=VersionTLS12'],
    env: [
      {
        name: 'METALLB_ML_SECRET_NAME',
        value: 'metallb-memberlist',
      },
      {
        name: 'METALLB_DEPLOYMENT',
        value: 'metallb-controller',
      },
      {
        name: 'METALLB_BGP_TYPE',
        value: 'frr',
      },
    ],
    ports: [
      {
        name: 'monitoring',
        containerPort: 7472,
      },
      {
        containerPort: 9443,
        name: 'webhook-server',
        protocol: 'TCP',
      },
    ],
    volumeMounts: [
      {
        mountPath: '/tmp/k8s-webhook-server/serving-certs',
        name: 'cert',
        readOnly: true,
      },
    ],
    livenessProbe: {
      httpGet: {
        path: '/metrics',
        port: 'monitoring',
      },
      initialDelaySeconds: 10,
      periodSeconds: 10,
      timeoutSeconds: 1,
      successThreshold: 1,
      failureThreshold: 3,
    },
    readinessProbe: {
      httpGet: {
        path: '/metrics',
        port: 'monitoring',
      },
      initialDelaySeconds: 10,
      periodSeconds: 10,
      timeoutSeconds: 1,
      successThreshold: 1,
      failureThreshold: 3,
    },
    securityContext: {
      allowPrivilegeEscalation: false,
      readOnlyRootFilesystem: true,
      capabilities: {
        drop: ['ALL'],
      },
    },
  },
  metallb_speaker_container:: {
    name: 'speaker',
    image: $._images.speaker,
    args: ['--port=7472', '--log-level=info'],
    env: [
      {
        name: 'METALLB_NODE_NAME',
        valueFrom: {
          fieldRef: {
            fieldPath: 'spec.nodeName',
          },
        },
      },
      {
        name: 'METALLB_HOST',
        valueFrom: {
          fieldRef: {
            fieldPath: 'status.hostIP',
          },
        },
      },
      {
        name: 'METALLB_ML_BIND_ADDR',
        valueFrom: {
          fieldRef: {
            fieldPath: 'status.podIP',
          },
        },
      },
      {
        name: 'METALLB_ML_LABELS',
        value: 'app.kubernetes.io/name=metallb,app.kubernetes.io/component=speaker',
      },
      {
        name: 'METALLB_ML_BIND_PORT',
        value: '7946',
      },
      {
        name: 'METALLB_ML_SECRET_KEY_PATH',
        value: '/etc/ml_secret_key',
      },
      {
        name: 'FRR_CONFIG_FILE',
        value: '/etc/frr_reloader/frr.conf',
      },
      {
        name: 'FRR_RELOADER_PID_FILE',
        value: '/etc/frr_reloader/reloader.pid',
      },
      {
        name: 'METALLB_BGP_TYPE',
        value: 'frr',
      },
      {
        name: 'METALLB_POD_NAME',
        valueFrom: {
          fieldRef: {
            fieldPath: 'metadata.name',
          },
        },
      },
    ],
    ports: [
      {
        name: 'monitoring',
        containerPort: 7472,
      },
      {
        name: 'memberlist-tcp',
        containerPort: 7946,
        protocol: 'TCP',
      },
      {
        name: 'memberlist-udp',
        containerPort: 7946,
        protocol: 'UDP',
      },
    ],
    livenessProbe: {
      httpGet: {
        path: '/metrics',
        port: 'monitoring',
      },
      initialDelaySeconds: 10,
      periodSeconds: 10,
      timeoutSeconds: 1,
      successThreshold: 1,
      failureThreshold: 3,
    },
    readinessProbe: {
      httpGet: {
        path: '/metrics',
        port: 'monitoring',
      },
      initialDelaySeconds: 10,
      periodSeconds: 10,
      timeoutSeconds: 1,
      successThreshold: 1,
      failureThreshold: 3,
    },
    securityContext: {
      allowPrivilegeEscalation: false,
      readOnlyRootFilesystem: true,
      capabilities: {
        drop: ['ALL'],
        add: ['NET_RAW'],
      },
    },
    volumeMounts: [
      {
        name: 'memberlist',
        mountPath: '/etc/ml_secret_key',
      },
      {
        name: 'reloader',
        mountPath: '/etc/frr_reloader',
      },
      {
        name: 'metallb-excludel2',
        mountPath: '/etc/metallb',
      },
    ],
  },

  metallbControllerServiceAccount:
    k.core.v1.serviceAccount.new('metallb-controller') + meta(k.core.v1.serviceAccount, 'controller'),

  metallbSpeakerServiceAccount:
    k.core.v1.serviceAccount.new('metallb-speaker') + meta(k.core.v1.serviceAccount, 'speaker'),

  metallbWebhookCertSecret: k.core.v1.secret.new('metallb-webhook-cert', {}) + meta(k.core.v1.secret),

  metallbExcludeL2ConfigMap:
    k.core.v1.configMap.new('metallb-excludel2', {
      'excludel2.yaml': |||
        announcedInterfacesToExclude:
        - ^docker.*
        - ^cbr.*
        - ^dummy.*
        - ^virbr.*
        - ^lxcbr.*
        - ^veth.*
        - ^lo$
        - ^cali.*
        - ^tunl.*
        - ^flannel.*
        - ^kube-ipvs.*
        - ^cni.*
        - ^nodelocaldns.*
      |||,
    })
    + meta(k.core.v1.configMap),

  metallbFrrStartupConfigMap:
    k.core.v1.configMap.new('metallb-frr-startup', {
      daemons: |||
        # This file tells the frr package which daemons to start.
        #
        # Sample configurations for these daemons can be found in
        # /usr/share/doc/frr/examples/.
        #
        # ATTENTION:
        #
        # When activating a daemon for the first time, a config file, even if it is
        # empty, has to be present *and* be owned by the user and group "frr", else
        # the daemon will not be started by /etc/init.d/frr. The permissions should
        # be u=rw,g=r,o=.
        # When using "vtysh" such a config file is also needed. It should be owned by
        # group "frrvty" and set to ug=rw,o= though. Check /etc/pam.d/frr, too.
        #
        # The watchfrr and zebra daemons are always started.
        #
        bgpd=yes
        ospfd=no
        ospf6d=no
        ripd=no
        ripngd=no
        isisd=no
        pimd=no
        ldpd=no
        nhrpd=no
        eigrpd=no
        babeld=no
        sharpd=no
        pbrd=no
        bfdd=yes
        fabricd=no
        vrrpd=no

        #
        # If this option is set the /etc/init.d/frr script automatically loads
        # the config via "vtysh -b" when the servers are started.
        # Check /etc/pam.d/frr if you intend to use "vtysh"!
        #
        vtysh_enable=yes
        zebra_options="  -A 127.0.0.1 -s 90000000 --limit-fds 100000"
        bgpd_options="   -A 127.0.0.1 -p 0 --limit-fds 100000"
        ospfd_options="  -A 127.0.0.1"
        ospf6d_options=" -A ::1"
        ripd_options="   -A 127.0.0.1"
        ripngd_options=" -A ::1"
        isisd_options="  -A 127.0.0.1"
        pimd_options="   -A 127.0.0.1"
        ldpd_options="   -A 127.0.0.1"
        nhrpd_options="  -A 127.0.0.1"
        eigrpd_options=" -A 127.0.0.1"
        babeld_options=" -A 127.0.0.1"
        sharpd_options=" -A 127.0.0.1"
        pbrd_options="   -A 127.0.0.1"
        staticd_options="-A 127.0.0.1 --limit-fds 100000"
        bfdd_options="   -A 127.0.0.1 --limit-fds 100000"
        fabricd_options="-A 127.0.0.1"
        vrrpd_options="  -A 127.0.0.1"

        # configuration profile
        #
        #frr_profile="traditional"
        #frr_profile="datacenter"

        #
        # This is the maximum number of FD's that will be available.
        # Upon startup this is read by the control files and ulimit
        # is called. Uncomment and use a reasonable value for your
        # setup if you are expecting a large number of peers in
        # say BGP.
        #MAX_FDS=1024

        # The list of daemons to watch is automatically generated by the init script.
        #watchfrr_options=""

        # for debugging purposes, you can specify a "wrap" command to start instead
        # of starting the daemon directly, e.g. to use valgrind on ospfd:
        #   ospfd_wrap="/usr/bin/valgrind"
        # or you can use "all_wrap" for all daemons, e.g. to use perf record:
        #   all_wrap="/usr/bin/perf record --call-graph -"
        # the normal daemon command is added to this at the end.
      |||,
      'vtysh.conf': 'service integrated-vtysh-config\n',
      'frr.conf': |||
        ! This file gets overriden the first time the speaker renders a config.
        ! So anything configured here is only temporary.
        frr version 8.0
        frr defaults traditional
        hostname Router
        line vty
        log file /etc/frr/frr.log informational
      |||,
    })
    + meta(k.core.v1.configMap, 'speaker'),

  metallbControllerClusterRole:
    rbac.clusterRole.new('metallb:controller')
    + meta(rbac.clusterRole, namespaced=false)
    + rbac.clusterRole.withRules([
      rule([''], ['services', 'namespaces'], ['get', 'list', 'watch']),
      rule([''], ['nodes'], ['list']),
      rule([''], ['services/status'], ['update']),
      rule([''], ['events'], ['create', 'patch']),
      rule(['admissionregistration.k8s.io'], ['validatingwebhookconfigurations'], ['create', 'delete', 'get', 'list', 'patch', 'update', 'watch'], ['metallb-webhook-configuration']),
      rule(['admissionregistration.k8s.io'], ['validatingwebhookconfigurations'], ['list', 'watch']),
      rule(['apiextensions.k8s.io'], ['customresourcedefinitions'], ['create', 'delete', 'get', 'list', 'patch', 'update', 'watch'], ['bfdprofiles.metallb.io', 'bgpadvertisements.metallb.io', 'bgppeers.metallb.io', 'ipaddresspools.metallb.io', 'l2advertisements.metallb.io', 'communities.metallb.io']),
      rule(['apiextensions.k8s.io'], ['customresourcedefinitions'], ['list', 'watch']),
    ]),

  metallbSpeakerClusterRole:
    rbac.clusterRole.new('metallb:speaker')
    + meta(rbac.clusterRole, namespaced=false)
    + rbac.clusterRole.withRules([
      rule([''], ['services', 'endpoints', 'nodes', 'namespaces'], ['get', 'list', 'watch']),
      rule(['discovery.k8s.io'], ['endpointslices'], ['get', 'list', 'watch']),
      rule([''], ['events'], ['create', 'patch']),
      rule(['metallb.io'], ['servicel2statuses', 'servicel2statuses/status'], ['*']),
    ]),

  metallbControllerClusterRoleBinding:
    rbac.clusterRoleBinding.new('metallb:controller')
    + meta(rbac.clusterRoleBinding, namespaced=false)
    + rbac.clusterRoleBinding.bindRole($.metallbControllerClusterRole)
    + rbac.clusterRoleBinding.withSubjects([rbac.subject.fromServiceAccount($.metallbControllerServiceAccount)]),

  metallbSpeakerClusterRoleBinding:
    rbac.clusterRoleBinding.new('metallb:speaker')
    + meta(rbac.clusterRoleBinding, namespaced=false)
    + rbac.clusterRoleBinding.bindRole($.metallbSpeakerClusterRole)
    + rbac.clusterRoleBinding.withSubjects([rbac.subject.fromServiceAccount($.metallbSpeakerServiceAccount)]),

  metallbPodListerRole:
    rbac.role.new('metallb-pod-lister')
    + meta(rbac.role)
    + rbac.role.withRules([
      rule([''], ['pods'], ['list', 'get']),
      rule([''], ['secrets'], ['get', 'list', 'watch']),
      rule([''], ['configmaps'], ['get', 'list', 'watch']),
      rule(['metallb.io'], ['bfdprofiles'], ['get', 'list', 'watch']),
      rule(['metallb.io'], ['bgppeers'], ['get', 'list', 'watch']),
      rule(['metallb.io'], ['l2advertisements'], ['get', 'list', 'watch']),
      rule(['metallb.io'], ['bgpadvertisements'], ['get', 'list', 'watch']),
      rule(['metallb.io'], ['ipaddresspools'], ['get', 'list', 'watch']),
      rule(['metallb.io'], ['communities'], ['get', 'list', 'watch']),
      rule(['metallb.io'], ['servicebgpstatuses', 'servicebgpstatuses/status'], ['*']),
    ]),

  metallbControllerRole:
    rbac.role.new('metallb-controller')
    + meta(rbac.role)
    + rbac.role.withRules([
      rule([''], ['secrets'], ['create', 'get', 'list', 'watch']),
      rule([''], ['secrets'], ['list'], ['metallb-memberlist']),
      rule(['apps'], ['deployments'], ['get'], ['metallb-controller']),
      rule([''], ['secrets'], ['create', 'delete', 'get', 'list', 'patch', 'update', 'watch']),
      rule(['metallb.io'], ['ipaddresspools'], ['get', 'list', 'watch']),
      rule(['metallb.io'], ['ipaddresspools/status'], ['update']),
      rule(['metallb.io'], ['bgppeers'], ['get', 'list']),
      rule(['metallb.io'], ['bgpadvertisements'], ['get', 'list']),
      rule(['metallb.io'], ['l2advertisements'], ['get', 'list']),
      rule(['metallb.io'], ['communities'], ['get', 'list', 'watch']),
      rule(['metallb.io'], ['bfdprofiles'], ['get', 'list', 'watch']),
    ]),

  metallbPodListerRoleBinding:
    rbac.roleBinding.new('metallb-pod-lister')
    + meta(rbac.roleBinding)
    + rbac.roleBinding.bindRole($.metallbPodListerRole)
    // As in the chart, without a namespace.
    + rbac.roleBinding.withSubjects([rbac.subject.withKind('ServiceAccount') + rbac.subject.withName('metallb-speaker')]),

  metallbControllerRoleBinding:
    rbac.roleBinding.new('metallb-controller')
    + meta(rbac.roleBinding)
    + rbac.roleBinding.bindRole($.metallbControllerRole)
    // As in the chart, without a namespace.
    + rbac.roleBinding.withSubjects([rbac.subject.withKind('ServiceAccount') + rbac.subject.withName('metallb-controller')]),

  metallbWebhookService:
    local svc = k.core.v1.service;
    svc.new('metallb-webhook-service', selector('controller'), [k.core.v1.servicePort.withPort(443) + k.core.v1.servicePort.withTargetPort(9443)])
    + meta(svc),

  metallbSpeakerDaemonSet:
    local d = k.apps.v1.daemonSet;
    local pod = d.spec.template.spec;
    d.new('metallb-speaker', [])
    + meta(d, 'speaker')
    // new() would add a `name` label; the selector is immutable and must stay as it was.
    + d.spec.selector.withMatchLabels(selector('speaker'))
    + d.spec.template.metadata.withLabels(selector('speaker'))
    + d.spec.updateStrategy.withType('RollingUpdate')
    + pod.withServiceAccountName('metallb-speaker')
    + pod.withTerminationGracePeriodSeconds(0)
    + pod.withHostNetwork(true)
    + pod.withVolumes([
      {
        name: 'memberlist',
        secret: {
          secretName: 'metallb-memberlist',
          defaultMode: 420,
        },
      },
      {
        name: 'metallb-excludel2',
        configMap: {
          defaultMode: 256,
          name: 'metallb-excludel2',
        },
      },
      {
        name: 'frr-sockets',
        emptyDir: {},
      },
      {
        name: 'frr-startup',
        configMap: {
          name: 'metallb-frr-startup',
        },
      },
      {
        name: 'frr-conf',
        emptyDir: {},
      },
      {
        name: 'reloader',
        emptyDir: {},
      },
      {
        name: 'metrics',
        emptyDir: {},
      },
    ])
    + pod.withInitContainers([
      {
        name: 'cp-frr-files',
        image: $._images.frr,
        securityContext: {
          runAsUser: 100,
          runAsGroup: 101,
        },
        command: ['/bin/sh', '-c', 'cp -rLf /tmp/frr/* /etc/frr/'],
        volumeMounts: [
          {
            name: 'frr-startup',
            mountPath: '/tmp/frr',
          },
          {
            name: 'frr-conf',
            mountPath: '/etc/frr',
          },
        ],
      },
      {
        name: 'cp-reloader',
        image: $._images.speaker,
        command: ['/cp-tool', '/frr-reloader.sh', '/etc/frr_reloader/frr-reloader.sh'],
        volumeMounts: [
          {
            name: 'reloader',
            mountPath: '/etc/frr_reloader',
          },
        ],
      },
      {
        name: 'cp-metrics',
        image: $._images.speaker,
        command: ['/cp-tool', '/frr-metrics', '/etc/frr_metrics/frr-metrics'],
        volumeMounts: [
          {
            name: 'metrics',
            mountPath: '/etc/frr_metrics',
          },
        ],
      },
    ])
    + pod.withShareProcessNamespace(true)
    + pod.withContainers([
      $.metallb_speaker_container,
      {
        name: 'frr',
        securityContext: {
          capabilities: {
            add: ['NET_ADMIN', 'NET_RAW', 'SYS_ADMIN', 'NET_BIND_SERVICE'],
          },
        },
        image: $._images.frr,
        env: [
          {
            name: 'TINI_SUBREAPER',
            value: 'true',
          },
        ],
        volumeMounts: [
          {
            name: 'frr-sockets',
            mountPath: '/var/run/frr',
          },
          {
            name: 'frr-conf',
            mountPath: '/etc/frr',
          },
        ],
        command: [
          '/bin/sh',
          '-c',
          |||
            /sbin/tini -- /usr/lib/frr/docker-start &
            attempts=0
            until [[ -f /etc/frr/frr.log || $attempts -eq 60 ]]; do
              sleep 1
              attempts=$(( $attempts + 1 ))
            done
            tail -f /etc/frr/frr.log
          |||,
        ],
        livenessProbe: {
          httpGet: {
            path: 'livez',
            port: 7473,
          },
          initialDelaySeconds: 10,
          periodSeconds: 10,
          timeoutSeconds: 1,
          successThreshold: 1,
          failureThreshold: 3,
        },
        startupProbe: {
          httpGet: {
            path: '/livez',
            port: 7473,
          },
          failureThreshold: 30,
          periodSeconds: 5,
        },
      },
      {
        name: 'reloader',
        image: $._images.frr,
        command: ['/etc/frr_reloader/frr-reloader.sh'],
        volumeMounts: [
          {
            name: 'frr-sockets',
            mountPath: '/var/run/frr',
          },
          {
            name: 'frr-conf',
            mountPath: '/etc/frr',
          },
          {
            name: 'reloader',
            mountPath: '/etc/frr_reloader',
          },
        ],
      },
      {
        name: 'frr-metrics',
        image: $._images.frr,
        command: ['/etc/frr_metrics/frr-metrics'],
        args: ['--metrics-port=7473'],
        env: [
          {
            name: 'VTYSH_HISTFILE',
            value: '/dev/null',
          },
        ],
        ports: [
          {
            containerPort: 7473,
            name: 'monitoring',
          },
        ],
        volumeMounts: [
          {
            name: 'frr-sockets',
            mountPath: '/var/run/frr',
          },
          {
            name: 'frr-conf',
            mountPath: '/etc/frr',
          },
          {
            name: 'metrics',
            mountPath: '/etc/frr_metrics',
          },
        ],
      },
    ])
    + pod.withNodeSelector({ 'kubernetes.io/os': 'linux' })
    + pod.withTolerations([
      {
        key: 'node-role.kubernetes.io/master',
        effect: 'NoSchedule',
        operator: 'Exists',
      },
      {
        key: 'node-role.kubernetes.io/control-plane',
        effect: 'NoSchedule',
        operator: 'Exists',
      },
    ]),

  metallbControllerDeployment:
    local d = k.apps.v1.deployment;
    local pod = d.spec.template.spec;
    // No replicas, as in the chart.
    d.new('metallb-controller', null, [$.metallb_controller_container])
    + meta(d, 'controller')
    // new() would add a `name` label; the selector is immutable and must stay as it was.
    + d.spec.selector.withMatchLabels(selector('controller'))
    + d.spec.template.metadata.withLabels(selector('controller'))
    + d.spec.strategy.withType('RollingUpdate')
    + pod.withServiceAccountName('metallb-controller')
    + pod.withTerminationGracePeriodSeconds(0)
    + pod.securityContext.withFsGroup(65534)
    + pod.securityContext.withRunAsNonRoot(true)
    + pod.securityContext.withRunAsUser(65534)
    + pod.withNodeSelector({ 'kubernetes.io/os': 'linux' })
    + pod.withVolumes([
      {
        name: 'cert',
        secret: {
          defaultMode: 420,
          secretName: 'metallb-webhook-cert',
        },
      },
    ]),

  metallbWebhook:
    local w = k.admissionregistration.v1.validatingWebhookConfiguration;
    w.new('metallb-webhook-configuration')
    + meta(w, namespaced=false)
    + w.withWebhooks([
      {
        admissionReviewVersions: ['v1'],
        clientConfig: {
          service: {
            name: 'metallb-webhook-service',
            namespace: ns,
            path: '/validate-metallb-io-v1beta2-bgppeer',
          },
        },
        failurePolicy: 'Fail',
        name: 'bgppeervalidationwebhook.metallb.io',
        rules: [
          {
            apiGroups: ['metallb.io'],
            apiVersions: ['v1beta2'],
            operations: ['CREATE', 'UPDATE'],
            resources: ['bgppeers'],
          },
        ],
        sideEffects: 'None',
      },
      {
        admissionReviewVersions: ['v1'],
        clientConfig: {
          service: {
            name: 'metallb-webhook-service',
            namespace: ns,
            path: '/validate-metallb-io-v1beta1-ipaddresspool',
          },
        },
        failurePolicy: 'Fail',
        name: 'ipaddresspoolvalidationwebhook.metallb.io',
        rules: [
          {
            apiGroups: ['metallb.io'],
            apiVersions: ['v1beta1'],
            operations: ['CREATE', 'UPDATE'],
            resources: ['ipaddresspools'],
          },
        ],
        sideEffects: 'None',
      },
      {
        admissionReviewVersions: ['v1'],
        clientConfig: {
          service: {
            name: 'metallb-webhook-service',
            namespace: ns,
            path: '/validate-metallb-io-v1beta1-bgpadvertisement',
          },
        },
        failurePolicy: 'Fail',
        name: 'bgpadvertisementvalidationwebhook.metallb.io',
        rules: [
          {
            apiGroups: ['metallb.io'],
            apiVersions: ['v1beta1'],
            operations: ['CREATE', 'UPDATE'],
            resources: ['bgpadvertisements'],
          },
        ],
        sideEffects: 'None',
      },
      {
        admissionReviewVersions: ['v1'],
        clientConfig: {
          service: {
            name: 'metallb-webhook-service',
            namespace: ns,
            path: '/validate-metallb-io-v1beta1-community',
          },
        },
        failurePolicy: 'Fail',
        name: 'communityvalidationwebhook.metallb.io',
        rules: [
          {
            apiGroups: ['metallb.io'],
            apiVersions: ['v1beta1'],
            operations: ['CREATE', 'UPDATE'],
            resources: ['communities'],
          },
        ],
        sideEffects: 'None',
      },
      {
        admissionReviewVersions: ['v1'],
        clientConfig: {
          service: {
            name: 'metallb-webhook-service',
            namespace: ns,
            path: '/validate-metallb-io-v1beta1-bfdprofile',
          },
        },
        failurePolicy: 'Fail',
        name: 'bfdprofilevalidationwebhook.metallb.io',
        rules: [
          {
            apiGroups: ['metallb.io'],
            apiVersions: ['v1beta1'],
            operations: ['CREATE', 'DELETE'],
            resources: ['bfdprofiles'],
          },
        ],
        sideEffects: 'None',
      },
      {
        admissionReviewVersions: ['v1'],
        clientConfig: {
          service: {
            name: 'metallb-webhook-service',
            namespace: ns,
            path: '/validate-metallb-io-v1beta1-l2advertisement',
          },
        },
        failurePolicy: 'Fail',
        name: 'l2advertisementvalidationwebhook.metallb.io',
        rules: [
          {
            apiGroups: ['metallb.io'],
            apiVersions: ['v1beta1'],
            operations: ['CREATE', 'UPDATE'],
            resources: ['l2advertisements'],
          },
        ],
        sideEffects: 'None',
      },
    ]),
}
