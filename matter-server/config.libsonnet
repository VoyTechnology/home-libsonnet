{
  _config+:: {
    // Name of the StatefulSet, Service and ServiceAccount. The volume claim is `data-<name>-0`, so never
    // change it on a live deployment.
    name: 'homeassistant-matter',

    // Host network interface used for Matter's mDNS and IPv6.
    networkInterface: error 'networkInterface must be set in the config',
    // Pin the pod to a node; null leaves scheduling to Kubernetes.
    nodeName: null,

    port: 5580,
    servicePort: 80,
    logLevel: 'info',

    // Size and class of the /data volume (fabric credentials). The volumeClaimTemplate is immutable.
    dataStorageSize: '10Gi',
    dataStorageClass: null,
  },
}
