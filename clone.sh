#!/bin/bash
# Usage: ./clone.sh [--group <group-path>] [--group-id <group-id>] [--code-dir <dir>]
# Requires: glab, git

set -e

# Defaults (match stale.sh)
DEFAULT_GROUP_PATH="premise-health/premise-development"
DEFAULT_GROUP_PATH_ENCODED="premise-health%2Fpremise-development"
DEFAULT_GROUP_ID="109214032"
DEFAULT_CODE_DIR="premise-health/premise-development"

# Helper to percent-encode slashes in group path
encode_group_path() {
  echo "$1" | sed 's/\//%2F/g'
}

# Parse flags
GROUP_PATH="$DEFAULT_GROUP_PATH"
GROUP_ID="$DEFAULT_GROUP_ID"
CODE_DIR="$DEFAULT_CODE_DIR"

while [[ $# -gt 0 ]]; do
  case $1 in
    --group)
      GROUP_PATH="$2"
      shift 2
      ;;
    --group-id)
      GROUP_ID="$2"
      shift 2
      ;;
    --code-dir)
      CODE_DIR="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--group <group-path>] [--group-id <group-id>] [--code-dir <dir>]"
      echo "  --group     GitLab group path (default: $DEFAULT_GROUP_PATH)"
      echo "  --group-id  GitLab group ID   (default: $DEFAULT_GROUP_ID)"
      echo "  --code-dir  Directory to clone repos into (default: $DEFAULT_CODE_DIR)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Expand ~ in code dir if present
CODE_DIR="${CODE_DIR/#\~/$HOME}"

# Encode group path for API calls
if [ "$GROUP_PATH" = "$DEFAULT_GROUP_PATH" ]; then
  GROUP_PATH_ENCODED="$DEFAULT_GROUP_PATH_ENCODED"
else
  GROUP_PATH_ENCODED="$(encode_group_path "$GROUP_PATH")"
fi

# Fetch all projects in group and subgroups
repos=$(glab api --paginate "groups/${GROUP_PATH_ENCODED}/projects?include_subgroups=true")
if [ $? -ne 0 ]; then
  echo "❌ Failed to fetch repositories. Make sure you're authenticated with 'glab auth login'"
  exit 1
fi

# Strip the group path prefix from .path_with_namespace
strip_prefix() {
  local full_path="$1"
  local prefix="$2"
  # Remove prefix and leading slash if present
  echo "${full_path#$prefix}" | sed 's/^\///'
}

# Iterate and clone each repo
# Only create subdirs for subgroups below the group

echo "$repos" | jq -r '.[] | "\(.ssh_url_to_repo)|\(.path_with_namespace)"' | while IFS='|' read -r repo_url repo_path; do
  # Remove the group path prefix
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
