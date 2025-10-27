# Specs Directory

This directory contains feature specifications created using Spec-Driven Development (SDD) workflow.

## Usage in Cursor

Use the following slash commands in Cursor IDE:

- `/specify "Feature description"` - Creates a new feature specification
- `/plan from spec: SPEC-001` - Generates an implementation plan from a specified feature
- `/tasks from plan: PLAN-001` - Creates implementation tasks based on the plan

## Spec File Format

Spec files should follow this structure:

```yaml
id: SPEC-001
title: Feature Title
status: draft
description: |
  Detailed description of the feature
requirements:
  - Requirement 1
  - Requirement 2
acceptance_criteria:
  - Criteria 1
  - Criteria 2
```

## Current Specs

No specifications created yet. Use Cursor slash commands to create new specs.
