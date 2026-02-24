# Commit Grouping Rules

When importing commit history into Jira cards, group commits **semantically** — by topic, feature area, or purpose — not chronologically or arbitrarily.

## Grouping Strategy

### 1. Prefix-based hints

Use conventional commit prefixes as primary grouping signals:

| Prefix | Meaning | Grouping behavior |
|--------|---------|-------------------|
| `feat:` | New feature | Group by feature name/area |
| `fix:` | Bug fix | Group by bug area or issue |
| `docs:` | Documentation | Group all docs changes together |
| `chore:` | Maintenance | Group by maintenance topic |
| `refactor:` | Code restructuring | Group by refactored area |
| `test:` | Tests | Group with the feature they test |
| `ci:` | CI/CD changes | Group all CI changes together |
| `style:` | Code style | Group with related feature or standalone |
| `perf:` | Performance | Group by optimized area |
| `build:` | Build system | Group all build changes together |

### 2. Semantic topic detection

When prefixes are absent or insufficient, analyze the commit message content:

- **Same file/module references** → likely related
- **Same domain terms** (e.g., "auth", "payment", "dashboard") → group together
- **Sequential fix iterations** (e.g., "fix login", "fix login redirect", "fix login session") → same card
- **Setup/config commits** (e.g., "add eslint", "configure prettier", "setup husky") → group as "Project setup"

### 3. Single-commit features

A commit that represents a complete, standalone change gets its **own card**:
- "feat: add user registration endpoint"
- "fix: resolve memory leak in websocket handler"

### 4. Multi-commit features

Related commits that build on each other get **one card** with all commits listed:
- "feat: add login form component" + "feat: add login API integration" + "fix: login validation error" → One card: "User login feature"

### 5. Card summary rules

- Keep summaries **concise but descriptive** (5-10 words)
- Use imperative mood: "Add user authentication" not "Added user authentication"
- Include the area/scope: "Add payment webhook handler" not "Add webhook"
- Don't repeat the prefix in the summary

### 6. Card description format

Each card's description should contain a table of its commits:

```
| Hash | Date | Author | Message |
|------|------|--------|---------|
| abc1234 | 2024-01-15 | Dev Name | feat: add login form |
| def5678 | 2024-01-16 | Dev Name | fix: login validation |
```

### 7. Maximum commits per card

- If a group has more than **15 commits**, consider splitting into logical sub-groups
- Each card should represent a **cohesive unit of work**

### 8. Ambiguous cases

When grouping is unclear:
- Prefer **fewer, larger cards** over many tiny ones
- Group by **time proximity** as a tiebreaker (commits within the same day/week)
- When in doubt, make it its own card — a standalone card is better than a misclassified one
