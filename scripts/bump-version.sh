#!/usr/bin/env bash
# Bump the app version and commit it.
#
# Usage: scripts/bump-version.sh <marketing-version> [build-number]
#   e.g. scripts/bump-version.sh 1.0.17        # build number is incremented
#        scripts/bump-version.sh 1.0.17 10     # explicit build number
#
# Updates MARKETING_VERSION in the Xcode project and CFBundleVersion in every
# target's Info.plist, then commits as "chore: bump version to X (build N)".
set -euo pipefail

cd "$(dirname "$0")/.."

PBXPROJ="AndroRingTrack.xcodeproj/project.pbxproj"
PLISTS=(
  "iOS/Info.plist"
  "AndroRingTrackWidget/Info.plist"
  "AndroRingTrackWatchWidget/Info.plist"
  "WatchAndroRingTrack/Info.plist"
  "WatchAndroRingTrack Extension/Info.plist"
)

usage() { echo "Usage: $0 <marketing-version> [build-number]" >&2; exit 1; }

[[ $# -ge 1 && $# -le 2 ]] || usage
NEW_VERSION="$1"
[[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid version '$NEW_VERSION' (expected X.Y.Z)" >&2; exit 1; }

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is not clean, commit or stash your changes first." >&2
  exit 1
fi

CURRENT_VERSION=$(grep -m1 -o 'MARKETING_VERSION = [0-9.]*' "$PBXPROJ" | awk '{print $3}')
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${PLISTS[0]}")

if [[ $# -eq 2 ]]; then
  NEW_BUILD="$2"
  [[ "$NEW_BUILD" =~ ^[0-9]+$ ]] || { echo "Invalid build number '$NEW_BUILD'" >&2; exit 1; }
else
  NEW_BUILD=$((CURRENT_BUILD + 1))
fi

echo "Version: $CURRENT_VERSION (build $CURRENT_BUILD) -> $NEW_VERSION (build $NEW_BUILD)"

sed -i '' "s/MARKETING_VERSION = ${CURRENT_VERSION};/MARKETING_VERSION = ${NEW_VERSION};/g" "$PBXPROJ"
# sed rather than PlistBuddy: PlistBuddy rewrites the whole file and reorders keys.
for plist in "${PLISTS[@]}"; do
  sed -i '' "/<key>CFBundleVersion<\/key>/{n;s|<string>[0-9]*</string>|<string>${NEW_BUILD}</string>|;}" "$plist"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" == "$NEW_BUILD" ]] \
    || { echo "CFBundleVersion was not updated in $plist" >&2; exit 1; }
done

# Sanity check: no stale version left behind.
if grep -q "MARKETING_VERSION = ${CURRENT_VERSION};" "$PBXPROJ" && [[ "$CURRENT_VERSION" != "$NEW_VERSION" ]]; then
  echo "Some MARKETING_VERSION entries were not updated." >&2
  exit 1
fi

git add "$PBXPROJ" "${PLISTS[@]}"
git commit -q -m "chore: bump version to ${NEW_VERSION} (build ${NEW_BUILD})"
echo "Committed: $(git log --oneline -1)"
