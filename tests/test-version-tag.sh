#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
mkdir -p "$T/repo/.github/scripts" "$T/repo/docs"
cp "$ROOT_DIR/.github/scripts/version-tag.sh" "$T/repo/.github/scripts/"
git init -q -b main "$T/repo"
git init -q --bare "$T/remote"
git -C "$T/repo" remote add origin "$T/remote"
git -C "$T/repo" config user.name PCG
git -C "$T/repo" config user.email pcg@test.local
write_version() {
  printf '%s\n' "$1" > "$T/repo/VERSION"
  printf '## %s\n\n- fix: test fixture.\n' "$1" > "$T/repo/docs/CHANGELOG.md"
}
run() { bash "$T/repo/.github/scripts/version-tag.sh" "$@"; }
for version in 0.7.30 0.8.0 1.0.0 30.20.30; do
  write_version "$version"
  run --check >/dev/null
done
for version in 0.7.31 0.21.0 31.0.0 00.8.1 v0.8.1 0.8; do
  write_version "$version"
  if run --check >/dev/null 2>&1; then echo "Accepted invalid version $version"; exit 1; fi
done
write_version 0.8.1
printf '## 0.8.0\n' > "$T/repo/docs/CHANGELOG.md"
if run --check >/dev/null 2>&1; then echo 'Accepted stale changelog'; exit 1; fi
write_version 0.8.1
git -C "$T/repo" add .
git -C "$T/repo" commit -qm fixture
sha="$(git -C "$T/repo" rev-parse HEAD)"
# A failed push leaves a local tag. Retrying must still publish it to the remote.
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/remote/hooks/pre-receive"
chmod +x "$T/remote/hooks/pre-receive"
if run --publish "$sha" > "$T/rejected" 2>&1; then echo 'Accepted rejected tag push'; exit 1; fi
[[ -z "$(git --git-dir="$T/remote" tag -l)" ]]
rm "$T/remote/hooks/pre-receive"
run --publish "$sha" >/dev/null
[[ "$(git --git-dir="$T/remote" rev-parse refs/tags/v0.8.1)" == "$sha" ]]
run --publish "$sha" >/dev/null
# Existing tags stay fixed when a later commit reuses VERSION.
printf 'later\n' > "$T/repo/other"
git -C "$T/repo" add other
git -C "$T/repo" commit -qm later
later="$(git -C "$T/repo" rev-parse HEAD)"
if run --publish "$later" > "$T/conflict" 2>&1; then echo 'Moved an existing tag'; exit 1; fi
[[ "$(git --git-dir="$T/remote" rev-parse refs/tags/v0.8.1)" == "$sha" ]]
# Uncommitted release metadata must never label a different committed version.
write_version 0.8.2
if run --publish "$later" >/dev/null 2>&1; then echo 'Tagged dirty metadata'; exit 1; fi
if run --publish "$sha" >/dev/null 2>&1; then echo 'Accepted wrong checkout target'; exit 1; fi
# An existing annotated tag at the expected commit is also an idempotent success.
git -C "$T/repo" add VERSION docs/CHANGELOG.md
git -C "$T/repo" commit -qm 'next version'
next="$(git -C "$T/repo" rev-parse HEAD)"
git -C "$T/repo" -c tag.gpgSign=false tag -a v0.8.2 -m fixture "$next"
git -C "$T/repo" push origin refs/tags/v0.8.2 >/dev/null
run --publish "$next" >/dev/null
# A failed remote lookup must fail even when a matching local tag exists.
git -C "$T/repo" remote set-url origin "$T/missing-remote"
if run --publish "$next" >/dev/null 2>&1; then echo 'Ignored failed remote lookup'; exit 1; fi
echo 'VERSION bounds, changelog, immutable tags and failed-push retry: PASS'
