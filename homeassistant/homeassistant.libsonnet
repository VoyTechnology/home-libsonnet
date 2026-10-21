// Home Assistant itself (formerly the pajikos/home-assistant Helm chart).
//
// PERSISTENCE: /config lives on the PVC created by the StatefulSet's
// volumeClaimTemplate. The StatefulSet name ('homeassistant'), the template name
// ('homeassistant') and its spec below MUST stay identical to what the chart
// rendered -- together they make the claim `homeassistant-homeassistant-0`, which is
// how the StatefulSet adopts the existing volume instead of creating a new one.
// The claim is deliberately not a rendered object (Argo never prunes it) and the
// retention policy below stops Kubernetes deleting it with the StatefulSet.
{
  local this = self,
  local cfg = $._config,
  local name = 'homeassistant',
  // Do not change: the StatefulSet selector is immutable and the Service and
  // ServiceMonitor select on it.
  local selector = {
    'app.kubernetes.io/name': name,
    'app.kubernetes.io/instance': name,
  },
  // Metadata labels. Kept apart from `selector`: the selector is immutable and must
  // never grow, while these may change freely.
  local labels = selector + { 'app.kubernetes.io/managed-by': 'Tanka' },
  // Host devices (name -> host path) mounted at the same path inside the container.
  local devices = $._config.devices,

  haServiceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: { name: name, labels: labels },
  },

  haService: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: { name: name, labels: labels },
    spec: {
      type: 'ClusterIP',
      ports: [{ name: 'http', port: cfg.port, targetPort: 'http', protocol: 'TCP' }],
      selector: selector,
    },
  },

  // Scrapes Home Assistant's Prometheus integration (`prometheus:` in configuration.yaml)
  // at /api/prometheus. HA requires auth on every request, so set `metricsTokenSecret`
  // to a { name, key } secret holding a long-lived access token.
  haServiceMonitor: if !cfg.metricsEnabled then {} else {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata: { name: name, labels: labels },
    spec: {
      endpoints: [{
        port: 'http',
        path: '/api/prometheus',
        interval: cfg.metricsInterval,
      } + (if cfg.metricsTokenSecret != null then { bearerTokenSecret: cfg.metricsTokenSecret } else {})],
      selector: { matchLabels: selector },
    },
  },

  haContainer:: {
    name: name,
    image: $._images.homeassistant,
    imagePullPolicy: 'IfNotPresent',
    ports: [{ name: 'http', containerPort: cfg.port, protocol: 'TCP' }],
    // Zigbee/Thread dongles need the extra permissions.
    securityContext: { privileged: true },
    livenessProbe: {
      httpGet: { path: '/', port: 'http', scheme: 'HTTP' },
      periodSeconds: 20,
      timeoutSeconds: 2,
      failureThreshold: 3,
      successThreshold: 1,
    },
    readinessProbe: {
      httpGet: { path: '/', port: 'http', scheme: 'HTTP' },
      periodSeconds: 10,
      timeoutSeconds: 1,
      failureThreshold: 3,
      successThreshold: 1,
    },
    volumeMounts:
      [{ name: name, mountPath: '/config' }]
      + [{ name: d, mountPath: devices[d] } for d in std.objectFields(devices)]
      + this.haProvisioningMounts,
  },

  haStatefulSet: {
    apiVersion: 'apps/v1',
    kind: 'StatefulSet',
    metadata: { name: name, labels: labels },
    spec: {
      serviceName: name,
      replicas: 1,
      selector: { matchLabels: selector },
      // Never let Kubernetes garbage-collect the /config claim (this is the
      // default; spelled out because the data on it is not reproducible).
      persistentVolumeClaimRetentionPolicy: { whenDeleted: 'Retain', whenScaled: 'Retain' },
      template: {
        metadata: {
          labels: labels,
        } + (if cfg.configuration != null then {
          // The configuration.yaml mount is a subPath, which never updates in place.
          annotations: { 'checksum/configuration': std.md5(this.haConfiguration) },
        } else {}),
        spec: {
          hostNetwork: true,
          serviceAccountName: name,
          containers: [this.haContainer],
          volumes:
            [{ name: d, hostPath: { path: devices[d] } } for d in std.objectFields(devices)]
            + this.haProvisioningVolumes,
        } + (if $._config.nodeName != null then {
          nodeSelector: { 'kubernetes.io/hostname': $._config.nodeName },
        } else {}),
      },
      // IMMUTABLE and identical to the Helm render: name + spec define the claim
      // (homeassistant-homeassistant-0) holding /config. No storageClassName: the
      // existing claim uses the cluster default.
      volumeClaimTemplates: [{
        metadata: { name: name },
        spec: {
          accessModes: ['ReadWriteOnce'],
          resources: { requests: { storage: cfg.storageSize } },
        },
      }],
    },
  },
}
