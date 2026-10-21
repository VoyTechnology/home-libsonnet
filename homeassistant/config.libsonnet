{
  _config+:: {
    domain: error 'domain must be set in the config',
    // Pin the pod to a node; null leaves scheduling to Kubernetes.
    nodeName: null,
    // Host devices passed through to Home Assistant, any number of them:
    // volume/mount name -> path on the node (also the path inside the container).
    devices: {},

    homeassistant: {
      port: 8123,
      ingressClass: 'external',
      // Size of the /config volume. This is the volumeClaimTemplate of the
      // StatefulSet, which is immutable: changing it needs a manual PVC resize.
      storageSize: '5Gi',
      // The ServiceMonitor scrapes /api/prometheus with this token.
      metricsTokenSecret: { name: 'homeassistant-matterhub', key: 'token' },
      metricsInterval: '30s',

      // Where the mixin ConfigMaps are mounted (one subdirectory per kind), see
      // provisioning.libsonnet.
      mixinPath: '/config/mixins',
    },
  },
}
