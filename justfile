# Each top-level directory with test/environments is a self-contained library.

# Render-test every library
test:
    #!/usr/bin/env bash
    set -euo pipefail
    for env in */test/environments; do
        just --justfile "${env%/test/environments}/justfile" --working-directory "${env%/test/environments}" test
    done

fmt:
    find . -name '*.libsonnet' -o -name '*.jsonnet' | xargs jsonnetfmt -i
