import json
import os
import urllib.request
from urllib.parse import quote

owner = os.environ["OWNER"]
repo = os.environ["REPO"].lower()
pr_number = os.environ["PR_NUMBER"]
base_ref = os.environ["BASE_REF"]
head_ref = os.environ["HEAD_REF"]
token = os.environ["GH_TOKEN"]

if base_ref != "main":
    print(f"Skipping cleanup for base={base_ref}, head={head_ref}")
    raise SystemExit(0)
if head_ref.startswith("hotfix/"):
    suffix = f"-hf.{pr_number}"
else:
    suffix = f"-pr.{pr_number}"

packages = [f"docker/{repo}", f"helm/{repo}"]
summary = os.environ.get("GITHUB_STEP_SUMMARY")


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


def write_summary(lines):
    if not summary:
        return
    with open(summary, "a") as handle:
        handle.write("\n".join(lines) + "\n")


write_summary(
    [
        "# 🧽 PR Artifact Cleanup",
        "",
        f"- PR: #{pr_number}",
        f"- Base: {base_ref}",
        f"- Head: {head_ref}",
        f"- Tag suffix: {suffix}",
        "",
    ]
)

for package in packages:
    package_path = quote(package, safe="")
    versions = []
    page = 1
    while True:
        url = (
            f"https://api.github.com/users/{owner}/packages/container/"
            f"{package_path}/versions?per_page=100&page={page}"
        )
        data = api_get(url)
        if data is None:
            write_summary([f"## Package: {package}", "- Package not found or access denied."])
            break
        if not data:
            break
        versions.extend(data)
        page += 1

    to_delete = []
    for version in versions:
        tags = tags_for(version)
        if any(tag.endswith(suffix) for tag in tags):
            to_delete.append((version["id"], tags))

    write_summary([f"## Package: {package}", "### Deleted versions"])

    if not to_delete:
        write_summary(["- None"])
        continue

    for vid, tags in to_delete:
        tag_list = ", ".join(tags) or "-"
        url = (
            f"https://api.github.com/users/{owner}/packages/container/"
            f"{package_path}/versions/{vid}"
        )
        req = urllib.request.Request(
            url,
            method="DELETE",
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/vnd.github+json",
            },
        )
        with urllib.request.urlopen(req) as resp:
            if resp.status not in (200, 204):
                raise RuntimeError(f"Delete failed for {vid}: {resp.status}")
        write_summary([f"- id {vid}: {tag_list}"])
