# Security Policy

## Reporting a Vulnerability

Please report security vulnerabilities to security@aintelligenttech.com.

We will respond within 48 hours and work with you to understand and address the
issue. Please provide:

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

## Sensitive Data Handling

Response Boxes stores session data locally at `~/.response-boxes/analytics/`.
This data may contain:

- **Code snippets** from AI responses
- **Project paths** and git remote URLs
- **Session metadata** (timestamps, session IDs)
- **Reasoning traces** (choices, assumptions, concerns)

### Recommendations

1. **Backup Exclusions**: Add `~/.response-boxes/` to backup exclusions if using
   cloud backup services (iCloud, Dropbox, Google Drive) to prevent accidental
   sync of sensitive project data.

2. **Periodic Review**: Review `boxes.jsonl` periodically to ensure no sensitive
   information (API keys, credentials, personal data) has been captured.

3. **Sensitive Projects**: For projects with strict confidentiality
   requirements, disable Response Boxes entirely:

   ```bash
   export RESPONSE_BOXES_DISABLED=true
   ```

4. **Project-Level Disable**: Add to your project's `.envrc` or shell config:

   ```bash
   # Disable Response Boxes for this project
   export RESPONSE_BOXES_DISABLED=true
   ```

## Data Lifecycle

### Collection

- Boxes are extracted from AI responses by agent-specific adapters:
  - Claude Code: SessionEnd hook parses the local transcript
  - OpenCode: plugin listens to message events
  - Windsurf/Cursor: response hooks collect from the assistant output
- Only structured box content is intended to be stored (not full transcripts), but
  response text may include code samples and project metadata depending on agent
  capabilities and configuration
- Collection is local-only; no data is sent to external servers

### Storage

- All data stored in plaintext JSONL format
- No encryption at rest (relies on filesystem permissions)
- Location: `~/.response-boxes/analytics/boxes.jsonl`

### Retention

- No automatic data expiration
- Manual cleanup: `rm ~/.response-boxes/analytics/boxes.jsonl`
- To preserve structure while clearing data:
  ```bash
  echo "" > ~/.response-boxes/analytics/boxes.jsonl
  ```

### Analysis

- `/analyze-boxes` runs locally using Claude
- Learnings are synthesized from local data only
- No external API calls beyond normal Claude Code usage

## Permissions

### File Permissions

The installer creates directories with standard permissions:

```bash
~/.response-boxes/          # 755
~/.response-boxes/analytics # 755
boxes.jsonl                 # 644
```

### Hook Execution

Hooks are bash scripts that execute with user permissions:

```bash
~/.claude/hooks/inject-context.sh    # 755
~/.claude/hooks/session-processor.sh # 755
```

Review hook scripts before installation if operating in a high-security
environment.

## Dependencies

Response Boxes requires:

- **jq**: For JSON processing (no network access)
- **bash**: Standard shell (no elevated privileges)
- **git**: Optional, for repository context

No external dependencies with network access are introduced.

## Known Limitations

1. **No encryption**: Event store is plaintext JSON
2. **No access control**: Anyone with filesystem access can read boxes
3. **Git remote exposure**: Repository URLs are stored in box context
4. **Code snippet capture**: Response content may include code samples

## Threat Model

### In Scope

- Local data storage security
- Hook script safety
- Dependency security

### Out of Scope

- Claude Code security (handled by Anthropic)
- Network-level attacks (no network functionality)
- Physical access attacks (filesystem permissions apply)

## Updates

Security updates will be announced via:

- GitHub Security Advisories
- CHANGELOG.md entries
- Repository releases

## Version

This security policy applies to Agent Response Boxes v0.7.1 and later.

---

Last updated: 2026-01-30
