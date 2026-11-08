{
  _images+:: {
    // renovate: datasource=docker depName=dxflrs/garage
    garage: 'dxflrs/garage:v2.5.0',
    // Runs the bootstrap Job: needs a shell, curl and jq (installed at start).
    // renovate: datasource=docker depName=alpine
    bootstrap: 'alpine:3.22.2',
  },
}
