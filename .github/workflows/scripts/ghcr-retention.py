import json
import os
import re
import urllib.request
from urllib.parse import quote

owner = os.environ["OWNER"]
repo = os.environ["REPO"].lower()
packages = [f"docker/{repo}", f"helm/{repo}"]
token = os.environ["GH_TOKEN"]
summary = os.environ["GITHUB_STEP_SUMMARY"]
semver_re = re.compile(r"^v?\d+\.\d+\.\d+$")


def api_get(url):
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
        },
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as err:
        if err.code == 404:
            return None
        raise


def tags_for(version):
    return version.get("metadata", {}).get("container", {}).get("tags", []) or []


def digest_for(version):
    container = version.get("metadata", {}).get("container", {}) or {}
    digest = container.get("digest") or version.get("name")
    return digest or "-"


def is_release_tag(tag):
    return bool(semver_re.match(tag))


def write_summary(lines):
    with open(summary, "a") as handle:
        handle.write("\n".join(lines) + "\n")


write_summary(
    [
        "# 🧹 GHCR Retention Report",
        "",
        "- Keep all release tags and delete untagged versions.",
        "",
    ]
)

for package in packages:
    versions = []
    missing_package = False
    page = 1
    while True:
        package_path = quote(package, safe="")
        url = (
            f"https://api.github.com/users/{owner}/packages/container/"
            f"{package_path}/versions?per_page=100&page={page}"
        )
        data = api_get(url)
        if data is None:
            missing_package = True
            break
        if not data:
            break
        versions.extend(data)
        page += 1

    protected_ids = set()
    untagged_versions = []

    for version in versions:
        tags = tags_for(version)
        if not tags:
            untagged_versions.append(version)
            continue
        if any(tag == "latest" or is_release_tag(tag) for tag in tags):
            protected_ids.add(version["id"])
            continue
    delete_versions = untagged_versions

    write_summary([f"## Package: {package}"])

    if missing_package:
        write_summary(["- Package not found or access denied."])
        print(f"Package not found: {package}")
        continue

    write_summary(["### Deleted versions"])

    if not delete_versions:
        write_summary(["- None"])
        print(f"No GHCR versions to delete for {package}.")
        continue

    for version in delete_versions:
        vid = version["id"]
        digest = digest_for(version)
        write_summary([f"- id {vid}: {digest}"])
        package_path = quote(package, safe="")
        url = f"https://api.github.com/users/{owner}/packages/container/{package_path}/versions/{vid}"
        req = urllib.request.Request(
            url,
            method="DELETE",
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/vnd.github+json",
            },
        )
        print(f"Deleting version {vid} from {package}")
        with urllib.request.urlopen(req) as resp:
            if resp.status not in (200, 204):
                raise RuntimeError(f"Delete failed for {vid}: {resp.status}")
