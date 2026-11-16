#!/bin/bash
# Show Clackey's downloads and repo traffic.   scripts/stats.sh
# Needs the GitHub CLI (gh) logged in. Uses the aakocval account if it's one of your logins.
set -euo pipefail
R=aakocval/clackey
export GH_TOKEN="${GH_TOKEN:-$(gh auth token --user aakocval 2>/dev/null || gh auth token)}"

echo "Downloads (per release file)"
gh api "repos/$R/releases" --jq '.[] | .tag_name as $t | .assets[] | "  \($t)  \(.name): \(.download_count)"'
gh api "repos/$R/releases" --jq '"  total: \([.[].assets[].download_count] | add // 0)"'

echo "Repo visits, last 14 days"
gh api "repos/$R/traffic/views" --jq '"  \(.count) views, \(.uniques) unique visitors"'

echo "Top referrers"
gh api "repos/$R/traffic/popular/referrers" --jq 'if length == 0 then "  (none yet)" else .[] | "  \(.referrer): \(.count) views, \(.uniques) unique" end'

gh api "repos/$R" --jq '"Stars: \(.stargazers_count)  Watchers: \(.subscribers_count)  Forks: \(.forks_count)"'
