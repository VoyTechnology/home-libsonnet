#!/usr/bin/env bash
# Renders every library's sample Tanka environments at a base ref and at the working tree, and prints
# a markdown report of what changes. Usage: scripts/diff.sh [base-ref]   (default: origin/main)
set -euo pipefail

base=${1:-origin/main}
rtk=${RTK:-rustanka}
root=$(git rev-parse --show-toplevel)
work=$(mktemp -d)
trap 'git -C "${root}" worktree remove --force "${work}/base" 2>/dev/null || true; rm -rf "${work}"' EXIT

git -C "${root}" worktree add --detach "${work}/base" "${base}" >/dev/null

render() { # <tree> <out>
    for f in "$1"/*/jsonnetfile.json; do
        if grep -q '"source"' "${f}"; then (cd "$(dirname "${f}")" && jb install >/dev/null); fi
    done
    for env in "$1"/*/test/environments/*; do
        [[ -d "${env}" ]] || continue
        rel=${env#"$1"/}
        mkdir -p "${2}/$(dirname "${rel}")"
        (cd "${env%/test/environments/*}" && ${rtk} show "${env}" --dangerous-allow-redirect) \
            >"${2}/${rel}.yaml" 2>"${2}/${rel}.err" || echo "render failed" >>"${2}/${rel}.yaml"
    done
}

render "${work}/base" "${work}/a"
render "${root}" "${work}/b"

changed=0
report=""
while IFS= read -r f; do
    rel=${f#"${work}/b/"}
    d=$(diff -u --label "base/${rel}" --label "head/${rel}" "${work}/a/${rel}" "${f}" 2>&1 || true)
    [[ -z "${d}" ]] && continue
    changed=1
    report+=$'\n'"<details><summary><code>${rel%.yaml}</code></summary>"$'\n\n```diff\n'"${d}"$'\n```\n\n</details>\n'
done < <(find "${work}/b" -name '*.yaml' | sort)

echo "## Rendered output diff vs \`${base}\`"
if ((changed)); then
    echo "${report}"
else
    echo "No change in any sample environment."
fi
