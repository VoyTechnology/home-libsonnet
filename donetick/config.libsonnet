{
  _config+:: {
    namespace: 'donetick',
    // Render the Namespace too. Leave off for namespaces managed elsewhere.
    createNamespace: false,

    // Name of the Deployment, Service and ConfigMap. The selector is immutable, never change it.
    name: 'donetick',

    // The host Donetick is reached on, e.g. chores.example.com.
    host: 'donetick.local',

    replicas: 1,

    // SQLite lives on this PVC. Swap `volumes` for another source instead.
    storage: {
      claimName: 'donetick-data-pvc',
      size: '10Gi',
      storageClassName: null,
    },

    // Secret with the DT_* variables (JWT secret, Telegram token). Never rendered here.
    secretName: 'donetick-secrets',
    // Secret with client_id and client_secret of the OIDC client, when `oauth2` is used.
    oidcSecretName: 'donetick-oidc-credentials',

    // Container resources. Empty leaves them unset.
    resources: {},
  },
}
