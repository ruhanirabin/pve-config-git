#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"
mode="${1:---check}"
if [[ "$mode" != --check && "$mode" != --publish ]]; then
  echo 'Usage: version-tag.sh --check | --publish COMMIT_SHA' >&2
  exit 1
fi
version="$(cat VERSION)"
if [[ ! "$version" =~ ^(0|[1-9][0-9]?)\.(0|[1-9][0-9]?)\.(0|[1-9][0-9]?)$ ]]; then
  echo 'VERSION must contain MAJOR.MINOR.PATCH without leading zeroes.' >&2
  exit 1
fi
if (( BASH_REMATCH[1] > 30 || BASH_REMATCH[2] > 20 || BASH_REMATCH[3] > 30 )); then
  echo 'VERSION exceeds the repository caps of 30.20.30.' >&2
  exit 1
fi
header="$(grep -m 1 '^## ' docs/CHANGELOG.md || true)"
if [[ "$header" != "## $version" ]]; then
  echo "The first changelog entry must be ## $version." >&2
  exit 1
fi
tag="v$version"
if [[ "$mode" == --check ]]; then
  echo "Validated $tag and its changelog entry."
  exit 0
fi
expected="${2:-}"
if [[ ! "$expected" =~ ^[0-9a-f]{40}$ && ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
  echo 'Publishing requires an explicit commit SHA.' >&2
  exit 1
fi
if [[ "$(git rev-parse HEAD)" != "$expected" ]]; then
  echo 'The checked-out commit differs from the requested tag target.' >&2
  exit 1
fi
git cat-file -e "$expected:VERSION"
git cat-file -e "$expected:docs/CHANGELOG.md"
if ! git diff --quiet "$expected" -- VERSION docs/CHANGELOG.md; then
  echo 'VERSION and the changelog must match the commit being tagged.' >&2
  exit 1
fi
# Check the remote separately from local tags left by a previously failed push.
remote="$(git ls-remote --refs origin "refs/tags/$tag")"
if [[ -n "$remote" ]]; then
  git fetch --no-tags origin "refs/tags/$tag"
  if [[ "$(git rev-parse 'FETCH_HEAD^{commit}')" == "$expected" ]]; then
    echo "$tag already points to $expected on origin."
    exit 0
  fi
  echo "$tag already exists on origin at a different commit. It will not be moved." >&2
  exit 1
fi
if git show-ref --verify --quiet "refs/tags/$tag"; then
  if [[ "$(git rev-parse "$tag^{commit}")" != "$expected" ]]; then
    echo "$tag exists locally at a different commit. It will not be moved." >&2
    exit 1
  fi
else
  git -c tag.gpgSign=false tag "$tag" "$expected"
fi
git push origin "refs/tags/$tag"
echo "Published $tag at $expected."
