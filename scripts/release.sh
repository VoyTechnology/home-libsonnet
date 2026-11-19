#!/usr/bin/env bash
# Tags every library that changed since its last `<lib>/vX.Y.Z` tag and (with --push) publishes a
# GitHub release for it. The bump comes from conventional commits touching the library's directory:
#   `type!:` or a BREAKING CHANGE footer -> major (minor while < 1.0.0)
#   `feat`                                -> minor (patch while < 1.0.0)
#   anything else                         -> patch
# Libraries without a tag start at v0.1.0.
set -euo pipefail

push=false
[[ "${1:-}" == "--push" ]] && push=true

for dir in */test/environments; do
    lib="${dir%%/*}"
    last=$(git tag --list "${lib}/v*" --sort=-v:refname | head -n1)
    range=${last:+${last}..}HEAD

    log=$(git log "${range}" --format='%H%x1f%s%x1f%b%x1e' -- "${lib}")
    [[ -z "${log//[[:space:]]/}" ]] && continue

    bump=patch
    while IFS=$'\x1f' read -r -d $'\x1e' _ subject body; do
        subject=${subject#$'\n'}
        if [[ "${subject}" =~ ^[a-z]+(\(.+\))?!: ]] || [[ "${body}" == *"BREAKING CHANGE"* ]]; then
            bump=major
        elif [[ "${subject}" =~ ^feat(\(.+\))?: && "${bump}" != major ]]; then
            bump=minor
        fi
    done <<<"${log}"

    if [[ -z "${last}" ]]; then
        next="0.1.0"
    else
        IFS=. read -r major minor patch <<<"${last#"${lib}"/v}"
        if ((major == 0)); then
            # 0.x: breaking -> minor, everything else -> patch
            [[ "${bump}" == patch ]] || bump=$([[ "${bump}" == major ]] && echo minor || echo patch)
        fi
        case "${bump}" in
            major) next="$((major + 1)).0.0" ;;
            minor) next="${major}.$((minor + 1)).0" ;;
            patch) next="${major}.${minor}.$((patch + 1))" ;;
        esac
    fi
    tag="${lib}/v${next}"

    notes=$(git log "${range}" --format='- %s (%h)' -- "${lib}")
    echo "${lib}: ${last:-<none>} -> ${tag} (${bump})"
    echo "${notes}"

    if ${push}; then
        git tag "${tag}"
        git push origin "refs/tags/${tag}"
        gh release create "${tag}" --title "${tag}" --notes "${notes}" --latest=false
    fi
done
