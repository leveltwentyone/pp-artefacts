In this repository, you will find artifacts related to various challenges in the Power Platform that I have encountered and where I would like to share the solutions with others.

## Repository Automation

This repository includes several agentic workflows that automate common tasks:

### Daily Repo Status

A daily workflow that creates upbeat status reports for the repository, gathering recent activity and providing insights:

- **Frequency**: Daily schedule + manual dispatch
- **Purpose**: Generate GitHub issues with repository activity summaries, including:
  - Recent repository activity (issues, PRs, discussions, releases, code changes)
  - Progress tracking and project highlights
  - Actionable recommendations for maintainers
- **Location**: `.github/workflows/daily-repo-status.md`

### Daily Documentation Updater

An automated documentation maintenance workflow that keeps documentation in sync with code changes:

- **Frequency**: Weekly schedule + manual dispatch
- **Purpose**: Automatically review merged pull requests and update documentation:
  - Scans for merged PRs from the last 24 hours
  - Identifies new features and changes that need documentation
  - Updates documentation files accordingly
  - Creates pull requests with documentation improvements
- **Location**: `.github/workflows/daily-doc-updater.md`

For more information about these workflows, see the workflow definition files in `.github/workflows/`.
