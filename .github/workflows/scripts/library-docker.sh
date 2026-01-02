#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"

init_context() {
  repo_name="${GITHUB_REPOSITORY##*/}"
  IMAGE_NAME="ghcr.io/${GITHUB_REPOSITORY_OWNER,,}/docker/${repo_name,,}"
  SHORT_SHA="${GITHUB_SHA::7}"
  RELEASE_VERSION=""
  if [ "${EVENT_KIND}" = "release" ]; then
    RELEASE_VERSION="${GITHUB_REF_NAME#v}"
  fi
  echo "IMAGE_NAME=${IMAGE_NAME}" >> "$GITHUB_ENV"
  echo "SHORT_SHA=${SHORT_SHA}" >> "$GITHUB_ENV"
  echo "RELEASE_VERSION=${RELEASE_VERSION}" >> "$GITHUB_ENV"
}

case "$cmd" in
  set-context)
    init_context
    echo "BUILD_CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$GITHUB_ENV"
    echo "EVENT_KIND=${EVENT_KIND}" >> "$GITHUB_ENV"
    ;;
  resolve-inputs)
    echo "IMAGE_VERSION=${IMAGE_VERSION_RAW}" >> "$GITHUB_ENV"
    if [ -n "${PUBLISHED_TAGS_RAW:-}" ]; then
      echo "PUBLISHED_TAGS=${PUBLISHED_TAGS_RAW}" >> "$GITHUB_ENV"
    fi
    if [ -n "${MANIFEST_CHECK_REFS_RAW:-}" ]; then
      {
        echo "MANIFEST_CHECK_REFS<<EOF"
        echo "${MANIFEST_CHECK_REFS_RAW}"
        echo "EOF"
      } >> "$GITHUB_ENV"
    fi
    ;;
  verify-manifest)
    if [ -n "${MANIFEST_CHECK_REFS:-}" ]; then
      while IFS= read -r ref; do
        if [ -n "$ref" ]; then
          docker buildx imagetools inspect "$ref" | grep -q 'linux/amd64'
          docker buildx imagetools inspect "$ref" | grep -q 'linux/arm64'
        fi
      done <<< "${MANIFEST_CHECK_REFS}"
    fi
    ;;
  smoke-test)
    platform_flag=""
    if [ "${MATRIX_ARCH}" = "arm64" ]; then
      platform_flag="--platform=linux/arm64"
    fi
    image_ref="${IMAGE_NAME}:${IMAGE_VERSION}"
    if docker run --rm ${platform_flag} --entrypoint /usr/bin/chromium "$image_ref" --version; then
      true
    elif docker run --rm ${platform_flag} --entrypoint /usr/bin/chromium-browser "$image_ref" --version; then
      true
    else
      echo "Chromium binary not found for smoke test." >&2
      exit 1
    fi
    docker run --rm ${platform_flag} --entrypoint /usr/bin/dumb-init "$image_ref" --version
    ;;
  cleanup-resolve-tags)
    echo "PUBLISHED_TAGS=${PUBLISHED_TAGS_RAW}" >> "$GITHUB_ENV"
    ;;
  cleanup-delete-tags)
    package_name="docker/$(echo "$REPO" | tr '[:upper:]' '[:lower:]')"
    tags_raw="${PUBLISHED_TAGS}"
    if [ -z "$tags_raw" ]; then
      echo "No published tags resolved; skipping cleanup."
      exit 0
    fi

    json="$(curl -fsSL -H "Authorization: Bearer ${GH_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/users/${OWNER}/packages/container/${package_name}/versions?per_page=100")"

    deleted_ids=""
    IFS=',' read -ra tags <<< "$tags_raw"
    for raw in "${tags[@]}"; do
      tag="$(echo "$raw" | xargs)"
      [ -n "$tag" ] || continue
      id="$(echo "$json" | jq -r --arg tag "$tag" '.[] | select(.metadata.container.tags[]? == $tag) | .id' | head -n1)"
      if [ -n "$id" ] && ! echo "$deleted_ids" | grep -q -w "$id"; then
        echo "Deleting GHCR package version id=$id for tag=$tag"
        curl -fsSL -X DELETE -H "Authorization: Bearer ${GH_TOKEN}" \
          -H "Accept: application/vnd.github+json" \
          "https://api.github.com/users/${OWNER}/packages/container/${package_name}/versions/${id}"
        deleted_ids="${deleted_ids} ${id}"
      else
        echo "No version found for tag=$tag (or already deleted)"
      fi
    done
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    exit 1
    ;;
esac
