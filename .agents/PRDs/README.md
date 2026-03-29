# Product Requirements Documents (PRDs)

**Purpose:** Product Requirements Documents define features, problems, and solutions before implementation.

**Last Updated:** 2026-01-10

---

## Quick Reference

PRDs are created when:
- Planning a new feature
- Addressing a problem that needs investigation
- Defining requirements before implementation

---

## PRD File Format

```markdown
# PRD: Title

**Status:** Draft / In Review / Approved / In Progress / Complete
**Created:** YYYY-MM-DD
**Last Updated:** YYYY-MM-DD
**Related Tasks:** `../TASKS/task-name.md` (optional)
**Priority:** P0 (Critical) / P1 (High) / P2 (Medium) / P3 (Low)

## Problem Statement

What problem are we solving? Why is this important?

## Current Implementation

What exists today? (If applicable)

## Requirements

### Functional Requirements
- Requirement 1
- Requirement 2

### Non-Functional Requirements
- Performance
- Security
- Usability

## Success Criteria

How do we know this is done?
- [ ] Criterion 1
- [ ] Criterion 2

## Deliverables

What artifacts will be produced?
- Document 1
- Code changes
- Tests

## Timeline

- Phase 1: Date
- Phase 2: Date
```

---

## PRD Statuses

- **Draft** - Initial creation, not yet reviewed
- **In Review** - Being reviewed by stakeholders
- **Approved** - Ready for implementation
- **In Progress** - Implementation has started
- **Complete** - Delivered and verified
- **Cancelled** - No longer needed

---

## Linking PRDs to Tasks

Tasks that implement a PRD should include:
```markdown
**Related PRD:** `../PRDs/prd-name.md`
```

PRDs can reference related tasks:
```markdown
**Related Tasks:** 
- `../TASKS/task-1.md`
- `../TASKS/task-2.md`
```

---

## Best Practices

1. Keep PRDs focused on *what* and *why*, not *how*
2. Define clear success criteria
3. Update status as PRD progresses
4. Link to related tasks for tracking implementation
5. Archive completed PRDs periodically

---

## File Naming

- Use lowercase with hyphens: `prd-feature-name.md`
- Be descriptive: `prd-security-review.md` not `prd-security.md`
- Prefix with `prd-` to distinguish from tasks
