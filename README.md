# Premise CLI Toolkit

This repository provides a command-line toolkit for managing GitLab repositories at Premise Health. It includes scripts for cloning all repositories in a group and for generating reports on stale branches. The toolkit is designed to streamline repo management and cleanup for engineering teams.

## Overview

The main entry point is the `premise.sh` script, which acts as a CLI dispatcher for all available commands:

```bash
./premise.sh <command> [options]
```

Available commands:

- `stale`  &mdash; Find and report stale branches across GitLab repositories
- `clone`  &mdash; Clone all repositories in a group/subgroups, preserving directory structure

See below for details on each command and usage examples.

---

## Commands

### `stale` &mdash; Find Stale Branches

Scans all repositories in a GitLab group (and subgroups) for branches that have not had commits in a specified number of days. Can output to terminal or as a markdown report.

**Usage:**

```bash
./premise.sh stale [options]
```

**Options:**

| Option                  | Description                                                        |
|-------------------------|--------------------------------------------------------------------|
| `-g`, `--group`         | GitLab group path (default: premise-health/premise-development)    |
| `-i`, `--group-id`      | GitLab group ID (default: 109214032)                              |
| `-d`, `--days`          | Number of days to consider a branch stale (default: 90)            |
| `-s`, `--search`        | Filter branches by name (regex)                                    |
| `-m`, `--markdown`      | Output report in markdown format (default: terminal)               |
| `-e`, `--hide-empty`    | Do not display repos with no stale branches                        |
| `-h`, `--help`          | Show help menu and exit                                            |

**Examples:**

```bash
# Basic usage (default: 90 days, default group)
./premise.sh stale

# Find branches older than 60 days, output as markdown
./premise.sh stale -d 60 -m

# Filter by branch name
./premise.sh stale -s feature
```

---

### `clone` &mdash; Clone All Repos in Group

Clones all repositories in a GitLab group (and subgroups), preserving the group/subgroup directory structure. Useful for onboarding or mass updates.

**Usage:**

```bash
./premise.sh clone [options]
```

**Options:**

| Option                  | Description                                                        |
|-------------------------|--------------------------------------------------------------------|
| `-g`, `--group`         | GitLab group path (default: premise-health/premise-development)    |
| `-i`, `--group-id`      | GitLab group ID (default: 109214032)                              |
| `-c`, `--code-dir`      | Directory to clone repos into (default: premise-health/premise-development) |
| `--ignore`              | Comma-separated list of repo names to skip                         |
| `-h`, `--help`          | Show help menu and exit                                            |

**Examples:**

```bash
# Clone all repos in the default group
./premise.sh clone

# Clone into a custom directory
./premise.sh clone -c ~/code/premise

# Ignore certain repos
./premise.sh clone --ignore repo1,repo2
```
