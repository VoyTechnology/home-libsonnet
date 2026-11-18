{
  _images+:: {
    // The omnibus image: Silo with a bundled PostgreSQL and Redis. Pre-release, so no tag is pinned.
    // renovate: datasource=docker depName=ghcr.io/silo-server/silo-server
    silo: 'ghcr.io/silo-server/silo-server:latest',
  },
}
