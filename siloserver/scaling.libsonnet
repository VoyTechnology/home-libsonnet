// Recommended CPU and memory, mixed into the container. Replicas are not scaled: there is one pod, with
// PostgreSQL and Redis inside it on a ReadWriteOnce volume. Change it with another mixin, e.g.
// `silo_container+:: container.resources.withLimits({ memory: '8Gi' })`.
local container = (import 'k.libsonnet').core.v1.container;

{
  // The bundled PostgreSQL tunes itself to the memory limit, so size the limit for it too. There is no
  // CPU limit: it only throttles the pod while the node has idle CPU. Transcoding is CPU heavy, so
  // raise the request or use a GPU when it is used.
  silo_container+::
    container.resources.withRequests({ cpu: '1', memory: '2Gi' })
    + container.resources.withLimits({ memory: '6Gi' }),
}
