# Lobs Dashboard Documentation

This directory contains design documents, UX planning, and architectural notes for the Lobs Dashboard project.

## Contents

### UX Improvement Plan

**[ux-improvement-plan.md](ux-improvement-plan.md)** — Comprehensive UX improvement roadmap

A detailed design document outlining planned improvements to the dashboard's user experience across four key areas:

1. **Enhanced Sync Visibility** — Make git/GitHub sync state immediately visible with real-time feedback
2. **Improved Inbox Experience** — Streamline artifact review with bulk actions, better filtering, and card-based layout
3. **Markdown-Aware Task Notes** — Split-view markdown editor with live preview and formatting toolbar
4. **Keyboard Shortcut Discoverability** — Dedicated shortcuts panel and better UI hints

**Status:** Design complete, ready for implementation  
**Size:** 31KB detailed design with implementation tasks, timelines, and success metrics

**Key Sections:**
- Current pain points analysis with code evidence
- Proposed solutions with mockups and specifications
- 20+ implementation tasks organized by component
- 5-phase implementation roadmap (5 weeks)
- Success metrics and testing strategy
- Technical considerations (performance, compatibility, accessibility)

**When to Read:**
- Planning UX improvements
- Before implementing sync status, inbox, markdown, or keyboard shortcut features
- Understanding current UX issues and their root causes
- Reviewing implementation priorities

---

## Related Documentation

Most documentation lives in the repository root for easy discovery:

### User Guides
- [../README.md](../README.md) — Installation, setup, and usage
- [../SETTINGS_MIGRATION.md](../SETTINGS_MIGRATION.md) — Settings architecture

### Developer Guides
- [../CONTRIBUTING.md](../CONTRIBUTING.md) — Development workflow and patterns
- [../COMMAND_PALETTE.md](../COMMAND_PALETTE.md) — Command palette guide
- [../PERFORMANCE_FIXES.md](../PERFORMANCE_FIXES.md) — Performance patterns

### Planning & Design
- [../TASKS.md](../TASKS.md) — Task tracking
- [../CHANGES.md](../CHANGES.md) — Recent changes summary
- [ux-improvement-plan.md](ux-improvement-plan.md) — UX roadmap (this directory)

---

## Contributing to Documentation

When adding new documentation:

1. **User-facing docs** → Root directory (README.md, guides, tutorials)
2. **Design/planning docs** → This `docs/` directory
3. **Update indexes** → Add links to main README and this file
4. **Use clear titles** → Help readers know what they'll learn
5. **Include dates** → Show when content was written/updated

See [CONTRIBUTING.md](../CONTRIBUTING.md) for writing style and standards.

---

**Last updated:** 2026-02-12
