#!/bin/bash
# Requires: glab, git, jq

# Script to clone all repositories within a GitLab group/subgroups preserving the directory structure

set -e


DEFAULT_GROUP_PATH="premise-health/premise-development"
DEFAULT_GROUP_PATH_ENCODED="premise-health%2Fpremise-development"
DEFAULT_GROUP_ID="109214032"
DEFAULT_CODE_DIR="premise-health/premise-development"
GROUP_PATH="$DEFAULT_GROUP_PATH"
GROUP_ID="$DEFAULT_GROUP_ID"
CODE_DIR="$DEFAULT_CODE_DIR"
IGNORE_REPOS=""

print_help() {
  cat <<EOF
Usage: premise clone [--group <group-path>] [--group-id <group-id>] [--code-dir <dir>] [--ignore <repo1,repo2,...>]

Clone all repositories within a GitLab group/subgroups, preserving directory structure.

Options:
  -g, --group       GitLab group path (default: $DEFAULT_GROUP_PATH)
  -i, --group-id    GitLab group ID   (default: $DEFAULT_GROUP_ID)
  -c, --code-dir    Directory to clone repos into (default: $DEFAULT_CODE_DIR)
  --ignore          Comma-separated list of repo names to skip
  -h, --help        Show this help menu and exit

Examples:
    # Clone all repos in the group into premise-health/premise-development
    premise clone -g premise-health/premise-development -c ~/code/premise

    # Clone all repos in a specific group ID into given directory
    premise clone -i 109214032 -c ~/code/premise

    # Ignore certain repos
    premise clone --ignore repo1,repo2

    # Show help
    premise clone --help

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

# Strip the group path prefix from .path_with_namespace
strip_prefix() {
  local full_path="$1"
  local prefix="$2"
  # Remove prefix and leading slash if present
  echo "${full_path#$prefix}" | sed 's/^\///'
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      print_help
      exit 0
      ;;
    -g|--group)
      GROUP_PATH="$2"
      shift 2
      ;;
    -i|--group-id)
      GROUP_ID="$2"
      shift 2
      ;;
    -c|--code-dir)
      CODE_DIR="$2"
      shift 2
      ;;
    --ignore)
      IGNORE_REPOS="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Expand ~ in code dir if present
CODE_DIR="${CODE_DIR/#\~/$HOME}"

# Ensure code directory exists
mkdir -p "$CODE_DIR"

# Encode group path for API calls
if [ "$GROUP_PATH" = "$DEFAULT_GROUP_PATH" ]; then
  GROUP_PATH_ENCODED="$DEFAULT_GROUP_PATH_ENCODED"
else
  GROUP_PATH_ENCODED="$(encode_group_path "$GROUP_PATH")"
fi

# Convert ignore list to array
IFS=',' read -r -a IGNORE_ARRAY <<< "$IGNORE_REPOS"

should_ignore() {
  local repo_name="$1"
  for ignore in "${IGNORE_ARRAY[@]}"; do
    if [[ "$repo_name" == "$ignore" ]]; then
      return 0
    fi
  done
  return 1
}

# Fetch all projects in group and subgroups
repos=$(glab api --paginate "groups/${GROUP_PATH_ENCODED}/projects?include_subgroups=true")
if [ $? -ne 0 ]; then
  echo "❌ Failed to fetch repositories. Make sure you're authenticated with 'glab auth login'"
  exit 1
fi

# Iterate and clone each repo
# Only create subdirs for subgroups below the group
echo "$repos" | jq -r '.[] | "\(.ssh_url_to_repo)|\(.path_with_namespace)|\(.name)"' | while IFS='|' read -r repo_url repo_path repo_name; do
  if should_ignore "$repo_name"; then
    echo "Ignoring repo: $repo_name"
    continue
  fi
  local_dir="$CODE_DIR/$(strip_prefix "$repo_path" "$GROUP_PATH")"
  if [ -d "$local_dir/.git" ]; then
    echo "Already cloned: $repo_path"
    continue
  fi
  mkdir -p "$local_dir"
  echo "Cloning $repo_url into $local_dir"
  git clone "$repo_url" "$local_dir"
done

echo "All repositories cloned into $CODE_DIR"
