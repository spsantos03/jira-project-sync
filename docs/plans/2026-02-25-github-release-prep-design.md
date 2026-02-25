# GitHub Release Prep Design

## Goal

Prepare the jira-project-sync plugin for public GitHub distribution with proper documentation, licensing, and release history.

## Deliverables

### 1. Root README.md

GitHub landing page with dual-audience structure:
- Quick Start at top for Claude Code power users (4 steps)
- Full setup guide below for newcomers (Atlassian MCP setup, installation, configuration)
- Configuration reference, how-it-works explanation
- MIT license badge

### 2. LICENSE

MIT license, 2026, Sergio Santos.

### 3. CHANGELOG.md

Single 1.0.0 entry covering all features built so far:
- Automatic sync hook
- init and onboard skills
- Semantic commit grouping
- Lazy transition discovery
- Per-project configuration

### 4. Inner README.md update

Fix outdated `transitionDoneId: "31"` to `null` with lazy discovery note in `plugins/jira-project-sync/README.md`.

## Non-goals

- No contributing guide (YAGNI)
- No CI/CD setup
- No npm/package manager distribution
- No additional plugin metadata changes (already correct)
