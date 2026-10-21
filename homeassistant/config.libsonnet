{
  _config+:: {
    // Pin the pod to a node; null leaves scheduling to Kubernetes.
    nodeName: null,
    // Host devices passed through to Home Assistant, any number of them:
    // volume/mount name -> path on the node (also the path inside the container).
    devices: {},

    port: 8123,
    // Size of the /config volume. This is the volumeClaimTemplate of the
    // StatefulSet, which is immutable: changing it needs a manual PVC resize.
    storageSize: '5Gi',

    // Home Assistant's configuration.yaml as a Jsonnet object. When set, the library
    // renders it to a ConfigMap mounted at /config/configuration.yaml and injects the
    // sections that load the mixins (see provisioning.libsonnet). Use `ha.include*`
    // for !include tags. When null, configuration.yaml is left alone (e.g. it lives on
    // the volume) and those sections have to be added by hand.
    configuration: null,

    // Where the mixin ConfigMaps are mounted (one subdirectory per kind).
    mixinPath: '/config/mixins',
    // Max bytes of data per ConfigMap when sharding mixins. Kubernetes caps a ConfigMap
    // at 1MiB; the default leaves headroom for metadata.
    mixinShardBytes: 900 * 1024,

    // ServiceMonitor for /api/prometheus. Needs the Prometheus Operator CRDs, and
    // `metricsTokenSecret` ({ name, key }) if the API requires a token.
    metricsEnabled: false,
    metricsInterval: '30s',
    metricsTokenSecret: null,
  },
}
