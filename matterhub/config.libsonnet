{
  _config+:: {
    // Name of the StatefulSet and Service. The volume claim is `data-<name>-0`, so never change it on a
    // live deployment.
    name: 'homeassistant-matterhub',

    // Secret with the Home Assistant URL and a long-lived access token. Never rendered here.
    secretName: 'homeassistant-matterhub',
    urlKey: 'url',
    tokenKey: 'token',

    // Pin the pod to a node; null leaves scheduling to Kubernetes.
    nodeName: null,
    // Cluster DNS address. The pod uses the host network, so it has to be told where cluster DNS is.
    clusterDNS: '10.43.0.10',

    port: 8482,
    logLevel: 'info',

    // Size and class of the /data volume (bridge and fabric state). The volumeClaimTemplate is immutable.
    dataStorageSize: '1Gi',
    dataStorageClass: null,
  },
}
