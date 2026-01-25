# Changelog

All notable changes to Claude Response Boxes will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.0] - 2026-01-25

### Breaking Changes

- **Removed 🪞 Sycophancy box** — Anti-sycophancy is now a sophisticated
  internal protocol based on research (ELEPHANT framework, SMART, self-blinding
  studies). It operates during response generation without visible output.

### Added

- `agents/claude-code/rules/anti-sycophancy.md` — Research-backed protocol with:
  - Five dimensions of sycophancy detection (ELEPHANT framework)
  - System 2 self-interrogation stages
  - Third-person perspective technique (63.8% efficacy)
  - Counterfactual checking
  - Banned phrases with replacements
  - Integration guidance with existing response boxes

### Changed

- Box count reduced from 13 to 12
- Existing Sycophancy boxes preserved in event store but filtered from context
  injection

### Research References

- [Towards Understanding Sycophancy](https://arxiv.org/abs/2310.13548)
- [ELEPHANT Framework](https://arxiv.org/html/2505.13995v2)
- [Self-Blinding Research](https://arxiv.org/html/2601.14553)
- [SMART Framework](https://arxiv.org/html/2509.16742v1)

### Migration

No action required. Sycophancy boxes will no longer appear in responses.
Historical Sycophancy boxes remain in the event store but are not projected.

## [0.5.0] - 2026-01-24

### Added

- GitHub Actions CI/CD pipeline with lint, bash tests, TypeScript tests
- Bash testing framework (bats) with 38 test cases
- TypeScript tests for OpenCode plugin with vitest
- Windsurf full-mode support with collection hook and injection workflow
- Cursor enhanced basic mode with collection hook and manual context skill
- OpenCode native skill distribution and static instructions
- Comprehensive cross-agent compatibility documentation
- SECURITY.md with vulnerability reporting and data handling guidelines
- GitHub issue templates (bug report, feature request, agent support)
- GitHub pull request template
- CODEOWNERS file

### Changed

- Consolidated repository structure (removed duplicate root-level directories)
- Improved OpenCode plugin with crypto-based ID generation
- Added session correlation via chat.headers hook
- Updated README with compatibility matrix and troubleshooting
- Updated architecture docs with multi-agent diagrams

### Fixed

- CODE_OF_CONDUCT.md contact information placeholder

## [4.0.0] - 2026-01-22

### Added

- Event-sourced architecture with `boxes.jsonl`
- AI-powered `/analyze-boxes` skill for pattern recognition
- Cross-session learning with recency decay
- Support for learning hierarchy (meta-learnings)
- OpenCode plugin for shared event store
- `BOX_RECENCY_DECAY` environment variable for configuring decay factor

### Changed

- Boxes stored as JSONL events instead of JSON array
- Learnings now synthesized from evidence with confidence tracking
- SessionStart hook projects learnings instead of raw boxes

### Removed

- Static `box-index.json` in favor of dynamic projection

## [3.0.0] - 2026-01-21

### Added

- Prompt-only architecture for agent-agnostic design
- Basic mode installation (`--basic` flag)
- Windsurf basic-mode rule support
- Cursor basic-mode rule support

### Changed

- Simplified installation to focus on rules and output styles
- Moved agent-specific files to `agents/` directory

### Removed

- Hard dependency on Claude Code hooks for basic mode

## [2.1.0] - 2026-01-20

### Added

- User/project installation scopes
- `--project` flag for project-level installation
- `--uninstall` flag for removing components
- Backup mechanism for modified files

### Changed

- Default installation scope is now user-level (`~/.claude/`)
- Installer detects and reports existing installation status

## [2.0.0] - 2026-01-19

### Added

- SessionStart hook for context injection (`inject-context.sh`)
- SessionEnd hook for box collection (`session-processor.sh`)
- Analytics directory (`~/.claude/analytics/`)
- `box-index.json` for tracking collected boxes
- `BOX_INJECT_LEARNINGS` and `BOX_INJECT_BOXES` environment variables

### Changed

- Hooks registered in `~/.claude/settings.json`
- Cross-session learning now automated via hooks

## [1.0.0] - 2026-01-15

### Added

- Initial release of Response Box System
- 13 box types (Choice, Decision, Assumption, Concern, Warning, Confidence,
  Pushback, Suggestion, Reflection, FollowUps, Completion, Quality, Sycophancy)
- Output style (`response-box.md`)
- Rules specification (`response-boxes.md`)
- CLAUDE.md snippet for integration
- Installation script with dry-run support

[Unreleased]:
  https://github.com/AIntelligentTech/agent-response-boxes/compare/v0.5.0...HEAD
[0.5.0]:
  https://github.com/AIntelligentTech/agent-response-boxes/compare/v4.0.0...v0.5.0
[4.0.0]:
  https://github.com/AIntelligentTech/agent-response-boxes/compare/v3.0.0...v4.0.0
[3.0.0]:
  https://github.com/AIntelligentTech/claude-response-boxes/compare/v2.1.0...v3.0.0
[2.1.0]:
  https://github.com/AIntelligentTech/claude-response-boxes/compare/v2.0.0...v2.1.0
[2.0.0]:
  https://github.com/AIntelligentTech/claude-response-boxes/compare/v1.0.0...v2.0.0
[1.0.0]:
  https://github.com/AIntelligentTech/claude-response-boxes/releases/tag/v1.0.0
