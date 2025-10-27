# Spec Kit Usage Guide for CVExcel

## Overview

This project now supports **Spec-Driven Development (SDD)** through Spec Kit integration with Cursor IDE. This allows you to use slash commands to create specifications, plans, and tasks directly within Cursor.

## What is Spec Kit?

Spec Kit enables you to:
- Create feature specifications using `/specify` commands
- Generate implementation plans from specs
- Create tasks from plans
- Maintain a structured development workflow

## Directory Structure

```
.spec/
├── spec-kit.yaml           # Spec Kit configuration
├── specs/                  # Feature specifications
│   └── README.md
├── plans/                  # Implementation plans
│   └── README.md
├── tasks/                  # Implementation tasks
│   └── README.md
└── snippets/               # Code templates
    ├── README.md
    ├── powershell_script_template.ps1
    └── vendor_module_template.ps1
```

## Using Spec Kit in Cursor

### 1. Create a Feature Specification

Type in Cursor chat:
```
/specify "Add support for Oracle security advisories"
```

This creates a specification file in `.spec/specs/` with:
- Feature title
- Description
- Requirements
- Acceptance criteria

### 2. Generate an Implementation Plan

From a specification:
```
/plan from spec: SPEC-001
```

This creates a plan in `.spec/plans/` outlining:
- Implementation approach
- Technical details
- Task breakdown

### 3. Create Tasks from Plan

From a plan:
```
/tasks from plan: PLAN-001
```

This creates individual tasks in `.spec/tasks/` for:
- Specific implementation steps
- Testing requirements
- Documentation updates

## Integration with Existing Tools

### AI Foreman Integration

The Spec Kit is integrated with your existing AI Foreman setup:

```yaml
ai_foreman:
  enabled: true
  config_path: ".ai/spec-pack.yaml"
  rules_path: ".ai/rules.yaml"
```

AI Foreman can now:
- Read specifications from `.spec/specs/`
- Generate plans based on specifications
- Create tasks aligned with project standards
- Ensure NIST security compliance

### Project Specifications

Your existing `spec-kit.yaml` is referenced in the Spec Kit configuration:

```yaml
project_specs: "spec-kit.yaml"
```

This ensures consistency between:
- Feature specifications (`.spec/specs/`)
- Project standards (`spec-kit.yaml`)
- AI Foreman rules (`.ai/rules.yaml`)

## Code Templates

### PowerShell Script Template

Located at `.spec/snippets/powershell_script_template.ps1`

Features:
- NIST SP 800-53 security guidelines
- Comprehensive error handling
- Structured logging
- XML documentation comments

### Vendor Module Template

Located at `.spec/snippets/vendor_module_template.ps1`

Features:
- Inherits from BaseVendor class
- Required method implementations
- Standardized error handling
- Follows existing vendor module patterns

## Workflow Example

### Step 1: Create Specification

```bash
# In Cursor chat
/specify "Add support for Docker security advisories"
```

Creates `SPEC-001.md` with:
- Feature description
- Requirements
- Acceptance criteria

### Step 2: Generate Plan

```bash
# In Cursor chat
/plan from spec: SPEC-001
```

Creates `PLAN-001.md` with:
- Implementation approach
- Technical architecture
- Task breakdown

### Step 3: Create Tasks

```bash
# In Cursor chat
/tasks from plan: PLAN-001
```

Creates multiple `TASK-*.md` files for:
- Creating DockerVendor.ps1 module
- Writing unit tests
- Updating documentation

### Step 4: Implement

1. Copy vendor template: `.spec/snippets/vendor_module_template.ps1`
2. Implement using tasks as guide
3. Follow PowerShell best practices from `spec-kit.yaml`
4. Ensure NIST security compliance

## Best Practices

### 1. Specification Writing

- Be specific about requirements
- Include acceptance criteria
- Reference existing project standards
- Consider security implications (NIST guidelines)

### 2. Plan Generation

- Break down into manageable tasks
- Consider dependencies
- Estimate complexity
- Include testing requirements

### 3. Task Implementation

- Follow PowerShell best practices
- Use provided templates
- Implement comprehensive error handling
- Write unit tests
- Update documentation

### 4. Security Considerations

Always ensure:
- Input validation
- Secure credential management
- Proper error handling
- Comprehensive logging
- NIST SP 800-53 compliance

## Troubleshooting

### Slash Commands Not Working

1. Ensure Cursor IDE is up to date
2. Verify Spec Kit is properly initialized
3. Check `.spec/spec-kit.yaml` configuration

### Template Issues

1. Templates are in `.spec/snippets/`
2. Use `.ps1` templates for PowerShell scripts
3. Follow BaseVendor pattern for vendor modules

### Integration Issues

1. Verify AI Foreman configuration in `.ai/`
2. Check project specifications in `spec-kit.yaml`
3. Review AI Foreman rules in `.ai/rules.yaml`

## Next Steps

1. **Try creating your first spec**: `/specify "Feature description"`
2. **Generate a plan**: `/plan from spec: SPEC-001`
3. **Create tasks**: `/tasks from plan: PLAN-001`
4. **Implement using templates**: Copy from `.spec/snippets/`

## Additional Resources

- [Project Specifications](spec-kit.yaml)
- [AI Foreman Integration](docs/AI_FOREMAN_INTEGRATION.md)
- [Vendor Module Guide](docs/VENDOR_MODULARIZATION_SUMMARY.md)
- [PowerShell Best Practices](.cursorrules)

## Support

For issues or questions:
1. Check existing documentation in `docs/`
2. Review AI Foreman logs in `.ai/state/`
3. Consult project specifications in `spec-kit.yaml`
