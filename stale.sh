#!/bin/bash

# Script to find stale branches across GitLab repositories
# Usage: ./stale-branches.sh [days_threshold] [group_id]

# Default threshold: 90 days
DAYS_THRESHOLD=${1:-90}
GROUP_ID=${2:-""}

# Calculate threshold date
if [[ "$(uname)" == "Darwin" ]]; then
    THRESHOLD_DATE=$(date -v-${DAYS_THRESHOLD}d +%Y-%m-%d)
    DATE_EPOCH() { date -j -f "%Y-%m-%d" "$1" +%s; }
    COMMIT_EPOCH() {
        local input="$1"
        # Remove milliseconds and convert timezone to +hhmm
        local fixed=$(echo "$input" | sed -E 's/([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})\.[0-9]+([+-][0-9]{2}):([0-9]{2})/\1\2\3/' | sed 's/Z$/+0000/')
        date -j -f "%Y-%m-%dT%H:%M:%S%z" "$fixed" +%s 2>/dev/null
    }
else
    THRESHOLD_DATE=$(date -d "${DAYS_THRESHOLD} days ago" +%Y-%m-%d)
    DATE_EPOCH() { date -d "$1" +%s; }
    COMMIT_EPOCH() {
        local input="$1"
        # Remove milliseconds and convert timezone to +hhmm
        local fixed=$(echo "$input" | sed -E 's/([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})\.[0-9]+([+-][0-9]{2}):([0-9]{2})/\1\2\3/' | sed 's/Z$/+0000/')
        date -d "$fixed" +%s 2>/dev/null
    }
fi

echo "🔍 Finding branches older than ${DAYS_THRESHOLD} days (before ${THRESHOLD_DATE})"
echo "=================================================="

# Function to check stale branches in a repository
check_repo_branches() {
    local repo_id=$1
    local repo_name=$2
    local found_stale=0

    echo "📁 Checking repository: ${repo_name}"

    # Get all branches for the repository
    branches=$(glab api "projects/${repo_id}/repository/branches")

    if [ $? -ne 0 ]; then
        echo "   ❌ Failed to fetch branches"
        return
    fi

    # Parse branches and check commit dates
    stale_output=""
    stale_branches=()
    while IFS='|' read -r branch_name commit_date; do
        if [ -n "$commit_date" ]; then
            commit_timestamp=$(COMMIT_EPOCH "$commit_date")
            threshold_timestamp=$(DATE_EPOCH "$THRESHOLD_DATE")
            if [[ "$commit_timestamp" =~ ^[0-9]+$ ]] && [[ "$threshold_timestamp" =~ ^[0-9]+$ ]]; then
                if [ "$commit_timestamp" -lt "$threshold_timestamp" ]; then
                    days_old=$(( ($(date +%s) - commit_timestamp) / 86400 ))
                        RED='\033[0;31m'
                        LIGHTYELLOW='\033[1;33m'
                        NC='\033[0m'
                        # Extract only the date part (YYYY-MM-DD) from commit_date
                        commit_date_only=$(echo "$commit_date" | cut -d'T' -f1)
                        stale_output+="   🕰️  STALE: ${RED}${branch_name}${NC} (${LIGHTYELLOW}${days_old} days old${NC}, last commit: ${commit_date_only})\n"
                    stale_branches+=("$branch_name")
                    found_stale=1
                fi
            fi
        fi
    done < <(echo "$branches" | jq -r '.[] | select(.name != "main" and .name != "master") | "\(.name)|\(.commit.committed_date)"')

    if [ "$found_stale" -eq 1 ]; then
        echo -e "$stale_output"
        if [ ${#stale_branches[@]} -gt 0 ]; then
            local_branches=$(printf "%s " "${stale_branches[@]}")
            remote_branches=$(printf "%s " "${stale_branches[@]}")
            GREEN='\033[1;32m'
            NC='\033[0m'
            echo "     # delete local and remote branches then prune remote-tracking branch (like origin/feature-xyz):"
            echo -e "     ${GREEN}git branch -D $local_branches && git push origin --delete $remote_branches && git fetch --prune${NC}"
            echo "     # delete remote branches only then prune remote-tracking branch (like origin/feature-xyz):"
            echo -e "     ${GREEN}git push origin --delete $remote_branches && git fetch --prune${NC}"
        fi
    else
        echo "   ✅ No stale branches found"
    fi
    echo ""
}

# Main execution

# Fetch all projects from the group and subgroups using glab (no --paginate)
GROUP_PATH="premise-health/premise-development"
GROUP_PATH_ENCODED="premise-health%2Fpremise-development"
echo "🏢 Scanning group: $GROUP_PATH"
repos=$(glab api "groups/${GROUP_PATH_ENCODED}/projects?include_subgroups=true")

if [ $? -ne 0 ]; then
    echo "❌ Failed to fetch repositories. Make sure you're authenticated with 'glab auth login'"
    exit 1
fi

# Process each repository
echo "$repos" | jq -r '.[] | "\(.id)|\(.name_with_namespace)"' | while IFS='|' read -r repo_id repo_name; do
    check_repo_branches "$repo_id" "$repo_name"
done

echo "🏁 Scan complete!"
