{
  _config+:: {
    // Name of the StatefulSet, Service and data volume claim (`data-<name>-0`). Never change it on a live
    // deployment: the claim name is how the pod finds its data.
    name: 'otbr',

    // The pod needs the Thread radio, so it is pinned to the node it is plugged into.
    nodeName: error 'nodeName must be set in the config',
    // Path of the radio on the node (also the path inside the container).
    threadDongle: error 'threadDongle must be set in the config',
    // Host network interface the Thread network is bridged to.
    networkInterface: error 'networkInterface must be set in the config',

    restPort: 8081,
    webPort: 8082,

    // Size and class of the /data volume. The StatefulSet's volumeClaimTemplate is immutable.
    dataStorageSize: '1Gi',
    dataStorageClass: null,
  },
}
