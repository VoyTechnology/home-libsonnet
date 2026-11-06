{
  _images+:: {
    // The controller image also runs the tunnels (--tunnel-image).
    // renovate: datasource=docker depName=ghcr.io/matheuscscp/cloudflare-gateway-controller
    controller: 'ghcr.io/matheuscscp/cloudflare-gateway-controller:v0.16.0',
  },
}
