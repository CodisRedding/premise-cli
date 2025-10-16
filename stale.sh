#!/bin/bash
# Requires: glab, git, jq

# Script to find stale branches across GitLab repositories

set -e

REPORTS_DIR="reports"
OUTPUT_FORMAT="terminal"
MARKDOWN_FILE="stale-branches-report.md"
DAYS_THRESHOLD=90
DEFAULT_GROUP_PATH="premise-health/premise-development"
DEFAULT_GROUP_ID="109214032"
GROUP_PATH="$DEFAULT_GROUP_PATH"
GROUP_ID=""
SEARCH_STRING=""
COMMAND_EXECUTED="$0 $@"
HIDE_EMPTY_REPOS=0

# Help menu function
print_help() {
    cat <<EOF
Usage: premise stale [options] [--group <group-path>] [--group-id <group-id>]

Find stale branches across GitLab repositories.

Options:
  -g, --group          GitLab group path (default: $DEFAULT_GROUP_PATH)
  -i, --group-id       GitLab group ID (default: $DEFAULT_GROUP_ID)
  -d, --days           Number of days to consider a branch stale (default: $DAYS_THRESHOLD)
  -s, --search         Filter branches by name (regex)
  -m, --markdown       Output report in markdown format (default: $OUTPUT_FORMAT)
  -e, --hide-empty     Do not display repositories with no stale branches found
  -h, --help           Show this help menu and exit

Examples:
    # Find branches older than 60 days in the default group
    premise stale -d 60

    # Find branches older than 30 days in a specific group ID, output as markdown
    premise stale -i 109214032 -d 30 -m

    # Find branches with 'feature' in the name older than 45 days
    premise stale -d 45 -s feature

    # Show help
    premise stale --help

Requirements:
  - glab (logged in): See https://glab.readthedocs.io/en/latest/quickstart.html
  - git: For cloning repositories
  - jq: For parsing JSON API responses
EOF
}

# Helper to percent-encode slashes in group path
encode_group_path() {
  echo "$1" | sed 's/\//%2F/g'
}

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
        if [ -n "$remote_branches" ]; then
            GREEN='\033[1;32m'
            NC='\033[0m'
            echo "     # delete remote branches"
            echo -ne "     ${GREEN}git push origin --delete"
            for branch in ${remote_branches}; do
                echo " \\"
                echo -n "       $branch"
            done
            echo " && \\"
            echo -e "     git fetch --prune${NC}"
        fi
        echo ""
    elif [ "$HIDE_EMPTY_REPOS" -ne 1 ]; then
        echo "📁 Checking repository: ${repo_name}"
        echo "   ✅ No stale branches found"
        echo ""
    fi
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
        if [ -n "$remote_branches" ]; then
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
    elif [ "$HIDE_EMPTY_REPOS" -ne 1 ]; then
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
    branches=$(glab api --paginate "projects/${repo_id}/repository/branches")
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

    # Collect branch name and commit date, sort by commit date descending
    if [ -n "$SEARCH_STRING" ]; then
        sorted_branches=$(echo "$branches" | jq -r ".[] | select(.name != \"main\" and .name != \"master\" and (.name | test(\"$SEARCH_STRING\"))) | \"\(.name)|\(.commit.committed_date)\"" | sort -t'|' -k2,2r)
    else
        sorted_branches=$(echo "$branches" | jq -r '.[] | select(.name != "main" and .name != "master") | "\(.name)|\(.commit.committed_date)"' | sort -t'|' -k2,2r)
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
    done <<< "$sorted_branches"

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

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            print_help
            exit 0
            ;;
        -m|--markdown)
            OUTPUT_FORMAT="markdown"
            shift
            ;;
        -g|--group)
            GROUP_PATH="$2"
            shift 2
            ;;
        -i|--group-id)
            GROUP_ID="$2"
            shift 2
            ;;
        -s|--search)
            SEARCH_STRING="$2"
            shift 2
            ;;
        -e|--hide-empty)
            HIDE_EMPTY_REPOS=1
            shift
            ;;
        -d|--days)
            DAYS_THRESHOLD="$2"
            shift 2
            ;;
        *)
            GROUP_PATH="$1"
            shift
            ;;
    esac
done

# Set default group id if neither group nor group-id is provided
if [ "$GROUP_PATH" = "$DEFAULT_GROUP_PATH" ] && [ -z "$GROUP_ID" ]; then
    GROUP_ID="$DEFAULT_GROUP_ID"
fi

# Set timestamped markdown file in reports dir if markdown output
if [ "$OUTPUT_FORMAT" = "markdown" ]; then
    mkdir -p "$REPORTS_DIR"
    TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
    MARKDOWN_FILE="${REPORTS_DIR}/${TIMESTAMP}-stale-branches-report.md"
fi

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
    if [ -n "$SEARCH_STRING" ]; then
        echo " | Search: \`${SEARCH_STRING}\`"
    fi
    echo "=================================================="
fi

# Encode group path or use group ID
if [ -n "$GROUP_ID" ]; then
    GROUP_REF="$GROUP_ID"
else
    GROUP_REF="$(encode_group_path "$GROUP_PATH")"
fi

repos=$(glab api --paginate "groups/${GROUP_REF}/projects?include_subgroups=true")

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
    echo "_Generated on $(date '+%Y-%m-%d %H:%M:%S')_" >> "$MARKDOWN_FILE"
    echo "" >> "$MARKDOWN_FILE"
    echo "**Command Used:**" >> "$MARKDOWN_FILE"
    echo "\`${COMMAND_EXECUTED}\`" >> "$MARKDOWN_FILE"
    echo "" >> "$MARKDOWN_FILE"
    echo "**Threshold:** Branches older than ${DAYS_THRESHOLD} days (before ${THRESHOLD_DATE})" >> "$MARKDOWN_FILE"
    if [ -n "$SEARCH_STRING" ]; then
        echo " | Search: \`${SEARCH_STRING}\`" >> "$MARKDOWN_FILE"
    fi
    echo "" >> "$MARKDOWN_FILE"
fi

# Process each repository
echo "$repos" | jq -r '.[] | "\(.id)|\(.name_with_namespace)"' | while IFS='|' read -r repo_id repo_name; do
    check_repo_branches "$repo_id" "$repo_name"
done

if [ "$OUTPUT_FORMAT" = "terminal" ]; then
    echo "🏁 Scan complete!"
else
    echo "Report saved to $MARKDOWN_FILE"
fi
