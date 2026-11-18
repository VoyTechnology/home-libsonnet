// Recommended CPU and memory. Replicas are not scaled: there is one pod, with PostgreSQL and Redis
// inside it on a ReadWriteOnce volume. Override with `_config+:: { silo+: { resources+: { ... } } }`.
{
  _config+:: {
    silo+: {
      // The bundled PostgreSQL tunes itself to the memory limit, so size the limit for it too.
      // No CPU limit: it only throttles the pod while the node has idle CPU. Transcoding is CPU heavy,
      // so raise the request or use a GPU when it is used.
      resources: {
        requests: { memory: '2Gi', cpu: 1 },
        limits: { memory: '6Gi' },
      },
    },
  },
}
