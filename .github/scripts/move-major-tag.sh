#!/usr/bin/env bash
# Points the major tag (v1) at the commit of release tag $TAG (v1.x.y), if
# $TAG is the newest release of that major. Needs GH_TOKEN with contents:
# write, REPO (owner/name) and TAG; DRY_RUN=true only reports.
set -euo pipefail

summary() {
  echo "$1"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then echo "$1" >> "$GITHUB_STEP_SUMMARY"; fi
}

if [[ ! "$TAG" =~ ^v([0-9]+)\.[0-9]+\.[0-9]+$ ]]; then
  summary "$TAG is not a vMAJOR.MINOR.PATCH release; no major tag to move."
  exit 0
fi
MAJOR="v${BASH_REMATCH[1]}"

# Only the newest *published, non-prerelease release* of this major moves it:
# a patch to an older line (v1.0.5 after v1.2.0) must not move v1 backwards,
# and a tag with no release yet, or a draft or prerelease, does not count.
NEWEST=$(gh api --paginate "repos/$REPO/releases" \
  --jq '.[] | select((.draft | not) and (.prerelease | not)) | .tag_name' \
  | grep -E "^$MAJOR\.[0-9]+\.[0-9]+$" | sort -V | tail -n 1 || true)
if [ "$NEWEST" != "$TAG" ]; then
  summary "$TAG is not the newest published $MAJOR release (${NEWEST:-none found}); $MAJOR stays where it is."
  exit 0
fi

# The commit behind the release tag (an annotated tag is dereferenced).
read -r TYPE SHA < <(gh api "repos/$REPO/git/ref/tags/$TAG" --jq '"\(.object.type) \(.object.sha)"')
if [ "$TYPE" = "tag" ]; then
  SHA=$(gh api "repos/$REPO/git/tags/$SHA" --jq '.object.sha')
fi

CURRENT=""
if REF=$(gh api "repos/$REPO/git/ref/tags/$MAJOR" --jq '"\(.object.type) \(.object.sha)"' 2>/dev/null); then
  read -r CTYPE CURRENT <<<"$REF"
  if [ "$CTYPE" = "tag" ]; then
    CURRENT=$(gh api "repos/$REPO/git/tags/$CURRENT" --jq '.object.sha')
  fi
fi

if [ "$CURRENT" = "$SHA" ]; then
  summary "$MAJOR already points at $TAG ($SHA)."
  exit 0
fi
if [ "${DRY_RUN:-false}" = "true" ]; then
  summary "Dry run: would move $MAJOR from ${CURRENT:-nothing} to $TAG ($SHA)."
  exit 0
fi
if [ -n "$CURRENT" ]; then
  gh api -X PATCH "repos/$REPO/git/refs/tags/$MAJOR" -f sha="$SHA" -F force=true >/dev/null
else
  gh api -X POST "repos/$REPO/git/refs" -f ref="refs/tags/$MAJOR" -f sha="$SHA" >/dev/null
fi
summary "Moved $MAJOR from ${CURRENT:-nothing} to $TAG ($SHA)."
