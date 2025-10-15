# Repo Cleanup

This repository contains scripts and reports to help identify and clean up stale branches in your Git repositories.

## Contents

- `stale.sh`: Shell script to generate stale branch reports.
- `reports/`: Directory containing markdown reports of stale branches.

## Usage

Run the script with various options to customize the report:

### Help Menu

You can display usage instructions and options by running:

```bash
./stale.sh --help
```

This will print a help menu describing all available options, defaults, and examples.

```bash
Usage: ./stale.sh [-d N] [-g group] [-i id] [-s term] [-m] [-e] [-h]

Options:
    -d, --days N         Number of days to consider a branch stale (default: 90)
    -g, --group PATH     GitLab group path (default: premise-health/premise-development)
    -i, --group-id ID    GitLab group ID (default: 109214032)
    -s, --search TERM    Filter branches by name (regex)
    -m, --markdown       Output report in markdown format (default: terminal)
    -e, --hide-empty     Do not display repositories with no stale branches found
    -h, --help           Show this help menu and exit

Examples:
    # Basic usage (default: 90 days, terminal output, default group)
    ./stale.sh

    # Set days threshold with flag
    ./stale.sh -d 120

    # Hide repos with no stale branches
    ./stale.sh -e

    # Output as markdown report (saved in reports/)
    ./stale.sh -m

    # Combine options (e.g., markdown report for branches older than 60 days, hide empty)
    ./stale.sh -m -e -d 60
```

### Example Output

**Terminal Output:**
![Terminal output example](term.png)

**Markdown Report Output:**
![Markdown report example](markdown.png)

## Requirements

- Git installed and accessible in your PATH
- [jq](https://stedolan.github.io/jq/) (JSON processor) installed and accessible in your PATH
- [glab](https://github.com/profclems/glab) (GitLab CLI) installed and accessible in your PATH

## Contributing

Feel free to submit issues or pull requests to improve the scripts or reporting process.

## License

MIT License
