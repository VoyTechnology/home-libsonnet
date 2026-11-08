// One-off setup through the admin API, safe to repeat: assigns the node its layout, imports the S3 key from
// a Secret (Garage generates keys itself otherwise, which a GitOps setup cannot read back) and creates the buckets.
{
  local cfg = $._config,
  local name = cfg.name,
  local script = |||
    set -eu
    apk add --no-cache curl jq >/dev/null
    api=http://%(name)s:3903
    call() { curl -sf -H "Authorization: Bearer $ADMIN_TOKEN" -H 'Content-Type: application/json' "$@"; }

    until status=$(call "$api/v2/GetClusterStatus"); do sleep 3; done
    if [ "$(echo "$status" | jq .layoutVersion)" = 0 ]; then
      node=$(echo "$status" | jq -r '.nodes[0].id')
      call -X POST "$api/v2/UpdateClusterLayout" -d "{\"roles\":[{\"id\":\"$node\",\"zone\":\"dc1\",\"capacity\":%(capacity)d,\"tags\":[]}]}" >/dev/null
      call -X POST "$api/v2/ApplyClusterLayout" -d '{"version":1}' >/dev/null
    fi

    call "$api/v2/GetKeyInfo?id=$ACCESS_KEY_ID" >/dev/null 2>&1 || \
      call -X POST "$api/v2/ImportKey" -d "{\"name\":\"bootstrap\",\"accessKeyId\":\"$ACCESS_KEY_ID\",\"secretAccessKey\":\"$SECRET_ACCESS_KEY\"}" >/dev/null

    for bucket in %(buckets)s; do
      id=$(call "$api/v2/GetBucketInfo?globalAlias=$bucket" 2>/dev/null | jq -r .id || true)
      if [ -z "$id" ]; then
        id=$(call -X POST "$api/v2/CreateBucket" -d "{\"globalAlias\":\"$bucket\"}" | jq -r .id)
      fi
      call -X POST "$api/v2/AllowBucketKey" \
        -d "{\"bucketId\":\"$id\",\"accessKeyId\":\"$ACCESS_KEY_ID\",\"permissions\":{\"read\":true,\"write\":true,\"owner\":false}}" >/dev/null
    done
  |||,

  // The bootstrap container. Extend it with a mixin.
  garage_bootstrap_container:: {
    local secretEnv(secret, var, key) = { name: var, valueFrom: { secretKeyRef: { name: secret, key: key } } },
    name: 'bootstrap',
    image: $._images.bootstrap,
    command: ['/bin/sh', '-c', script % {
      name: name,
      capacity: cfg.layoutCapacity,
      buckets: std.join(' ', cfg.buckets),
    }],
    env: [
      secretEnv(cfg.secretName, 'ADMIN_TOKEN', 'admin-token'),
      secretEnv(cfg.s3KeySecretName, 'ACCESS_KEY_ID', 'access-key-id'),
      secretEnv(cfg.s3KeySecretName, 'SECRET_ACCESS_KEY', 'secret-access-key'),
    ],
  },

  // A Job's template is immutable: Flux recreates it (kustomize.toolkit.fluxcd.io/force) when the image or script change.
  garageBootstrapJob: {
    apiVersion: 'batch/v1',
    kind: 'Job',
    metadata: {
      name: name + '-bootstrap',
      namespace: cfg.namespace,
      annotations: { 'kustomize.toolkit.fluxcd.io/force': 'enabled' },
    },
    spec: {
      backoffLimit: 20,
      template: {
        spec: { restartPolicy: 'OnFailure', containers: [$.garage_bootstrap_container] },
      },
    },
  },
}
