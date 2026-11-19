# Each top-level directory with test/environments is a self-contained library.

# Install jsonnet dependencies for libraries that declare any (vendored into <lib>/vendor)
deps:
    #!/usr/bin/env bash
    set -euo pipefail
    for f in */jsonnetfile.json; do
        if grep -q '"source"' "$f"; then (cd "${f%/jsonnetfile.json}" && jb install); fi
    done

# Render-test every library
test:
    #!/usr/bin/env bash
    set -euo pipefail
    for env in */test/environments; do
        just --justfile "${env%/test/environments}/justfile" --working-directory "${env%/test/environments}" test
    done

fmt:
    find . -name '*.libsonnet' -o -name '*.jsonnet' | xargs jsonnetfmt -i
