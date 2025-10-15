#!/bin/bash

# Script to find stale branches across GitLab repositories
# Usage: ./stale-branches.sh [days_threshold] [group_id]



# Output format: 'terminal' (default) or 'markdown'
OUTPUT_FORMAT="terminal"
MARKDOWN_FILE="stale-branches-report.md"
DAYS_THRESHOLD=90
GROUP_ID=""

# Parse options and positional arguments robustly
while [[ $# -gt 0 ]]; do
    case $1 in
        --markdown)
            OUTPUT_FORMAT="markdown"
            shift
            ;;
        --markdown-file)
            OUTPUT_FORMAT="markdown"
            MARKDOWN_FILE="$2"
            shift 2
            ;;
        [0-9]*)
            DAYS_THRESHOLD="$1"
            shift
            ;;
        *)
            GROUP_ID="$1"
            shift
            ;;
    esac
done

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


if [ "$OUTPUT_FORMAT" = "terminal" ]; then
    echo "🔍 Finding branches older than ${DAYS_THRESHOLD} days (before ${THRESHOLD_DATE})"
    echo "=================================================="
fi


# Output formatter: terminal
format_terminal_repo() {
    local repo_name="$1"
    local stale_output="$2"
    local local_branches="$3"
    local remote_branches="$4"
    local found_stale="$5"
    if [ "$found_stale" -eq 1 ]; then
        echo "📁 Checking repository: ${repo_name}"
        echo -e "$stale_output"
        if [ -n "$local_branches" ]; then
            GREEN='\033[1;32m'
            NC='\033[0m'
            echo "     # delete local and remote branches then prune remote-tracking branch (like origin/feature-xyz):"
            echo -e "     ${GREEN}git branch -D $local_branches && git push origin --delete $remote_branches && git fetch --prune${NC}"
            echo "     # delete remote branches only then prune remote-tracking branch (like origin/feature-xyz):"
            echo -e "     ${GREEN}git push origin --delete $remote_branches && git fetch --prune${NC}"
        fi
    else
        echo "📁 Checking repository: ${repo_name}"
        echo "   ✅ No stale branches found"
    fi
    echo ""
}

# Output formatter: markdown
format_markdown_repo() {
    local repo_name="$1"
    local stale_output="$2"
    local local_branches="$3"
    local remote_branches="$4"
    local found_stale="$5"
    if [ "$found_stale" -eq 1 ]; then
        echo -e "## Repository: $repo_name\n" >> "$MARKDOWN_FILE"
        echo -e "$stale_output" >> "$MARKDOWN_FILE"
        if [ -n "$local_branches" ]; then
            echo -e "**Delete local and remote branches, then prune remote-tracking branches:**" >> "$MARKDOWN_FILE"
            echo -e "\n\`\`\`bash" >> "$MARKDOWN_FILE"
            echo -n "git branch -D" >> "$MARKDOWN_FILE"
            for branch in ${local_branches}; do
                echo " \\" >> "$MARKDOWN_FILE"
                echo -n "  $branch" >> "$MARKDOWN_FILE"
            done
            echo " && \\" >> "$MARKDOWN_FILE"
            echo -n "git push origin --delete" >> "$MARKDOWN_FILE"
            for branch in ${remote_branches}; do
                echo " \\" >> "$MARKDOWN_FILE"
                echo -n "  $branch" >> "$MARKDOWN_FILE"
            done
            echo " && \\" >> "$MARKDOWN_FILE"
            echo "git fetch --prune" >> "$MARKDOWN_FILE"
            echo -e "\`\`\`\n" >> "$MARKDOWN_FILE"
            echo -e "**Delete remote branches, then prune remote-tracking branches:**" >> "$MARKDOWN_FILE"
            echo -e "\n\`\`\`bash" >> "$MARKDOWN_FILE"
            echo -n "git push origin --delete" >> "$MARKDOWN_FILE"
            for branch in ${remote_branches}; do
                echo " \\" >> "$MARKDOWN_FILE"
                echo -n "  $branch" >> "$MARKDOWN_FILE"
            done
            echo " && \\" >> "$MARKDOWN_FILE"
            echo "git fetch --prune" >> "$MARKDOWN_FILE"
            echo -e "\`\`\`\n" >> "$MARKDOWN_FILE"
        fi
    else
        echo -e "## Repository: $repo_name\n" >> "$MARKDOWN_FILE"
        echo -e "✅ No stale branches found\n" >> "$MARKDOWN_FILE"
    fi
}

# Function to check stale branches in a repository
check_repo_branches() {
    local repo_id=$1
    local repo_name=$2
    local found_stale=0
    local stale_output=""
    local_branches=""
    remote_branches=""
    RED='\033[0;31m'
    LIGHTYELLOW='\033[1;33m'
    NC='\033[0m'

    # Get all branches for the repository
    branches=$(glab api "projects/${repo_id}/repository/branches")
    if [ $? -ne 0 ]; then
        if [ "$OUTPUT_FORMAT" = "markdown" ]; then
            echo -e "## Repository: $repo_name\n" >> "$MARKDOWN_FILE"
            echo -e "❌ Failed to fetch branches\n" >> "$MARKDOWN_FILE"
        else
            echo "📁 Checking repository: ${repo_name}"
            echo "   ❌ Failed to fetch branches"
        fi
        return
    fi

    stale_branches=()
    while IFS='|' read -r branch_name commit_date; do
        if [ -n "$commit_date" ]; then
            commit_timestamp=$(COMMIT_EPOCH "$commit_date")
            threshold_timestamp=$(DATE_EPOCH "$THRESHOLD_DATE")
            if [[ "$commit_timestamp" =~ ^[0-9]+$ ]] && [[ "$threshold_timestamp" =~ ^[0-9]+$ ]]; then
                if [ "$commit_timestamp" -lt "$threshold_timestamp" ]; then
                    days_old=$(( ($(date +%s) - commit_timestamp) / 86400 ))
                    commit_date_only=$(echo "$commit_date" | cut -d'T' -f1)
                    if [ "$OUTPUT_FORMAT" = "markdown" ]; then
                        stale_output+="- **${branch_name}** (${days_old} days old, last commit: ${commit_date_only})\n"
                    else
                        stale_output+="   🕰️  STALE: ${RED}${branch_name}${NC} (${LIGHTYELLOW}${days_old} days old${NC}, last commit: ${commit_date_only})\n"
                    fi
                    stale_branches+=("$branch_name")
                    found_stale=1
                fi
            fi
        fi
    done < <(echo "$branches" | jq -r '.[] | select(.name != "main" and .name != "master") | "\(.name)|\(.commit.committed_date)"')

    if [ ${#stale_branches[@]} -gt 0 ]; then
        local_branches=$(printf "%s " "${stale_branches[@]}")
        remote_branches=$(printf "%s " "${stale_branches[@]}")
    else
        local_branches=""
        remote_branches=""
    fi

    if [ "$OUTPUT_FORMAT" = "markdown" ]; then
        format_markdown_repo "$repo_name" "$stale_output" "$local_branches" "$remote_branches" "$found_stale"
    else
        format_terminal_repo "$repo_name" "$stale_output" "$local_branches" "$remote_branches" "$found_stale"
    fi
}

echo "🏁 Scan complete!"
# Main execution

# Fetch all projects from the group and subgroups using glab (no --paginate)
GROUP_PATH="premise-health/premise-development"
GROUP_PATH_ENCODED="premise-health%2Fpremise-development"
if [ "$OUTPUT_FORMAT" = "terminal" ]; then
    echo "🏢 Scanning group: $GROUP_PATH"
fi
repos=$(glab api "groups/${GROUP_PATH_ENCODED}/projects?include_subgroups=true")

if [ $? -ne 0 ]; then
    if [ "$OUTPUT_FORMAT" = "markdown" ]; then
        echo "❌ Failed to fetch repositories. Make sure you're authenticated with 'glab auth login'" > "$MARKDOWN_FILE"
    else
        echo "❌ Failed to fetch repositories. Make sure you're authenticated with 'glab auth login'"
    fi
    exit 1
fi

# If markdown, clear the file and add a header
if [ "$OUTPUT_FORMAT" = "markdown" ]; then
    echo "# Stale Branches Report" > "$MARKDOWN_FILE"
    echo "_Generated on $(date '+%Y-%m-%d %H:%M:%S')_
" >> "$MARKDOWN_FILE"
fi

# Process each repository
echo "$repos" | jq -r '.[] | "\(.id)|\(.name_with_namespace)"' | while IFS='|' read -r repo_id repo_name; do
    check_repo_branches "$repo_id" "$repo_name"
done

if [ "$OUTPUT_FORMAT" = "terminal" ]; then
    echo "🏁 Scan complete!"
else
    echo "\n---\n" >> "$MARKDOWN_FILE"
    echo "Report saved to $MARKDOWN_FILE"
fi
