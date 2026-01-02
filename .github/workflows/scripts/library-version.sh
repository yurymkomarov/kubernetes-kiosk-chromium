#!/usr/bin/env bash
set -euo pipefail

output_file="${OUTPUT_FILE:-${GITHUB_OUTPUT}}"

write_output() {
  local key="$1"
  local value="$2"
  if [ -z "$output_file" ]; then
    echo "${key}=${value}"
  else
    echo "${key}=${value}" >> "$output_file"
  fi
}

short_sha="${GITHUB_SHA::7}"
kind="${VERSION_KIND:-}"
pr_id="${PR_ID:-}"
release_type="${RELEASE_TYPE:-}"
chart_version=""
image_tag=""
release_version=""

git fetch --tags --force
latest=$(git tag --list 'v*' | sort -V | tail -n1 || true)
if [ -z "$latest" ]; then
  major=0
  minor=0
  patch=0
else
  ver=${latest#v}
  IFS='.' read -r major minor patch <<< "$ver"
  major=${major:-0}
  minor=${minor:-0}
  patch=${patch:-0}
fi

case "$kind" in
  pr-main)
    minor=$((minor+1))
    patch=0
    base="${major}.${minor}.${patch}"
    if [ -z "$pr_id" ]; then
      echo "Missing pr_id for version_kind=pr-main" >&2
      exit 1
    fi
    chart_version="${base}-pr.${pr_id}"
    image_tag="${base}-pr.${short_sha}"
    ;;
  release-manual)
    case "$release_type" in
      major)
        major=$((major+1))
        minor=0
        patch=0
        ;;
      minor|"")
        minor=$((minor+1))
        patch=0
        ;;
      patch)
        patch=$((patch+1))
        ;;
      *)
        echo "Unknown release_type: $release_type" >&2
        exit 1
        ;;
    esac
    release_version="${major}.${minor}.${patch}"
    chart_version="${release_version}"
    image_tag="${release_version}"
    ;;
  none|pr|"")
    ;;
  *)
    echo "Unknown version_kind: $kind" >&2
    exit 1
    ;;
esac

write_output "short_sha" "${short_sha}"
write_output "chart_version" "${chart_version}"
write_output "image_tag" "${image_tag}"
write_output "release_version" "${release_version}"
