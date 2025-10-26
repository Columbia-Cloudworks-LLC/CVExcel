# AI Foreman Integration with Cursor Chat

This document describes the AI Foreman integration with Cursor chat for idempotent development on the CVExcel project.

## Overview

AI Foreman is an automated code maintenance system that:
- Analyzes code quality and security compliance
- Plans improvements based on NIST security guidelines
- Applies changes idempotently through git branches
- Integrates with Cursor chat for seamless development workflow

## Architecture

```
CVExcel/
├── .ai/                          # AI Foreman configuration
│   ├── spec-pack.yaml           # Spec Kit configuration
│   ├── rules.yaml               # AI Foreman rules
│   ├── checks/                  # Analysis scripts
│   │   ├── extract_api.ps1
│   │   ├── find_dead_links.ps1
│   │   ├── comment_vs_impl.ps1
│   │   ├── cursor_chat_monitor.ps1
│   │   ├── vendor_module_analysis.ps1
│   │   └── security_audit.ps1
│   ├── planners/                 # Planning scripts
│   │   ├── plan_docs_sync.ps1
│   │   ├── plan_fix_dead_links.ps1
│   │   ├── plan_comment_updates.ps1
│   │   ├── plan_cursor_chat_changes.ps1
│   │   ├── plan_vendor_improvements.ps1
│   │   └── plan_security_fixes.ps1
│   └── state/                    # State and results
├── ai-foreman.ps1               # Main AI Foreman script
├── cursor-chat-integration.ps1  # Cursor chat integration
├── .cursorrules                  # Cursor workspace rules
└── cursor-workspace.json         # Cursor workspace configuration
```

## Features

### 1. Automated Code Analysis
- **API Documentation Sync**: Ensures README/API docs reflect exported commands
- **Dead Link Detection**: Finds and fixes broken links in documentation
- **Comment Accuracy**: Validates that comments match implementation
- **Vendor Module Analysis**: Analyzes vendor modules for improvement opportunities
- **Security Audit**: Performs NIST security compliance audits

### 2. Cursor Chat Integration
- **Request Submission**: Submit development requests through Cursor chat
- **Idempotent Processing**: Ensures consistent, repeatable results
- **Automated Testing**: All changes are tested before application
- **Git Integration**: Changes are applied via feature branches

### 3. Security Compliance
- **NIST SP 800-53**: Follows NIST security guidelines
- **Input Validation**: Ensures proper input validation and sanitization
- **Error Handling**: Implements secure error handling practices
- **Audit Logging**: Maintains comprehensive security audit trails

## Usage

### Running AI Foreman Manually

```powershell
# Run AI Foreman with verbose logging
.\ai-foreman.ps1 -VerboseLog

# Check AI Foreman status
Get-Content .ai\state\fp.json | ConvertFrom-Json

# View AI Foreman logs
Get-Content docs\AI_FOREMAN_LOG.md
```

### Using Cursor Chat Integration

```powershell
# Add a new feature
.\cursor-chat-integration.ps1 -Type "add_feature" -Description "Add support for Oracle security advisories"

# Fix a bug
.\cursor-chat-integration.ps1 -Type "fix_bug" -Description "Fix Microsoft vendor scraping for new MSRC page layout"

# Improve scraping
.\cursor-chat-integration.ps1 -Type "improve_scraping" -Description "Enhance Playwright integration for JavaScript-heavy pages"

# Security fix
.\cursor-chat-integration.ps1 -Type "security_fix" -Description "Implement NIST security guidelines compliance"

# Documentation update
.\cursor-chat-integration.ps1 -Type "documentation" -Description "Update API documentation for new vendor modules"

# Vendor module improvements
.\cursor-chat-integration.ps1 -Type "vendor_module" -Description "Improve error handling in all vendor modules"
```

### Request Types

| Type | Description | Example |
|------|-------------|---------|
| `add_feature` | Add new functionality | "Add support for Oracle security advisories" |
| `fix_bug` | Fix existing bugs | "Fix Microsoft vendor scraping for new MSRC page layout" |
| `improve_scraping` | Enhance web scraping | "Enhance Playwright integration for JavaScript-heavy pages" |
| `security_fix` | Implement security improvements | "Implement NIST security guidelines compliance" |
| `documentation` | Update documentation | "Update API documentation for new vendor modules" |
| `vendor_module` | Improve vendor-specific modules | "Improve error handling in all vendor modules" |

## Configuration

### Spec Kit Configuration (`.ai/spec-pack.yaml`)

```yaml
version: 1
pack_id: "cvexcel/ai-foreman@1.1.0"
models:
  primary: "gpt-4o@2025-08"
  reviewer: "gpt-4o-mini@2025-08"
  cursor_chat: "gpt-4o@2025-08"
determinism:
  seed: 42
  temperature: 0.1
  max_tokens: 4000
policies:
  no_op_if_benefit_score_below: 0.60
  require_green_tests: true
  require_changed_lines_min: 1
  max_changed_lines: 500
```

### AI Foreman Rules (`.ai/rules.yaml`)

```yaml
rules:
  - id: cursor-chat-integration
    category: "development"
    description: "Handle Cursor chat requests for code changes and improvements."
    check: { run: "pwsh .ai/checks/cursor_chat_monitor.ps1" }
    plan:  { run: "pwsh .ai/planners/plan_cursor_chat_changes.ps1 -Request .ai/state/cursor-request.json" }
    judgment_tests:
      - "pwsh ./tests/run-all-tests.ps1"
      - "pwsh -Command 'Get-ChildItem vendors/*.ps1 | ForEach-Object { Write-Host \"Testing $_\"; & $_ -Test }'"
    acceptance:
      require_benefit_score_min: 0.60
      cursor_chat_approval: true
```

## Workflow

### 1. Request Submission
- User submits request through Cursor chat
- Request is saved to `.ai/state/cursor-request.json`
- AI Foreman monitors for new requests

### 2. Analysis Phase
- AI Foreman runs all check scripts
- Analysis results are saved to `.ai/state/`
- Planners generate improvement plans

### 3. Planning Phase
- Planners analyze results and generate unified diffs
- Plans are evaluated for benefit score
- Only high-value changes are selected

### 4. Application Phase
- Changes are applied via git feature branch
- Automated tests are run
- Changes are reverted if tests fail

### 5. Completion Phase
- Successful changes are committed
- Pull request is created
- Fingerprint is updated

## Security Features

### NIST Compliance
- **SI-10**: Input validation and sanitization
- **SA-15**: Secure coding practices
- **IA-5**: Credential handling
- **SI-11**: Error handling
- **AU-2**: Audit logging
- **SC-12**: Secure random number generation

### Automated Security Checks
- Input validation analysis
- Code injection vulnerability detection
- Hardcoded credential detection
- Error handling compliance
- Audit logging requirements
- SQL injection prevention
- Path traversal prevention
- XSS prevention

## Testing

### Automated Testing
- **Pester**: PowerShell unit testing
- **Playwright**: Web automation testing
- **PSScriptAnalyzer**: Code quality analysis
- **Security Tests**: NIST compliance validation

### Test Commands
```powershell
# Run all tests
pwsh ./tests/run-all-tests.ps1

# Test vendor integration
pwsh ./tests/test-vendor-integration.ps1

# Test Playwright functions
pwsh ./tests/test-playwright-functions.ps1

# Security compliance test
pwsh ./tests/test-security-compliance.ps1

# PSScriptAnalyzer
pwsh -Command 'Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error'
```

## Monitoring and Logging

### AI Foreman Logs
- **Main Log**: `docs/AI_FOREMAN_LOG.md`
- **Fingerprint**: `.ai/state/fp.json`
- **State Files**: `.ai/state/*.json`

### Cursor Chat Logs
- **Request Log**: `.ai/state/cursor-chat.log`
- **Request State**: `.ai/state/cursor-request.json`

### GitHub Actions
- **Workflow**: `.github/workflows/ai-foreman.yml`
- **Schedule**: Daily at 12:00 UTC (weekdays)
- **Manual Trigger**: Available via GitHub Actions UI

## Troubleshooting

### Common Issues

1. **AI Foreman Not Running**
   ```powershell
   # Check if all required files exist
   Test-Path .ai/spec-pack.yaml
   Test-Path .ai/rules.yaml
   Test-Path ai-foreman.ps1
   ```

2. **Cursor Chat Integration Not Working**
   ```powershell
   # Check request file
   Get-Content .ai/state/cursor-request.json

   # Check integration script
   .\cursor-chat-integration.ps1 -Type "add_feature" -Description "Test request"
   ```

3. **Tests Failing**
   ```powershell
   # Run tests manually
   pwsh ./tests/run-all-tests.ps1

   # Check specific test
   pwsh ./tests/test-vendor-integration.ps1
   ```

### Debug Mode
```powershell
# Run AI Foreman with verbose logging
.\ai-foreman.ps1 -VerboseLog

# Run Cursor chat integration with verbose logging
.\cursor-chat-integration.ps1 -Type "add_feature" -Description "Test" -Verbose
```

## Best Practices

### 1. Request Clarity
- Provide clear, specific descriptions
- Include relevant file paths when possible
- Use appropriate priority levels

### 2. Security First
- Always consider security implications
- Follow NIST guidelines
- Implement proper error handling

### 3. Testing
- Ensure all changes are tested
- Use automated testing where possible
- Validate security compliance

### 4. Documentation
- Update documentation with changes
- Maintain comprehensive logs
- Document any manual interventions

## Contributing

### Adding New Checks
1. Create check script in `.ai/checks/`
2. Add corresponding planner in `.ai/planners/`
3. Update rules in `.ai/rules.yaml`
4. Test the integration

### Adding New Request Types
1. Update `cursor-chat-integration.ps1`
2. Modify `plan_cursor_chat_changes.ps1`
3. Update documentation
4. Test the workflow

## Support

### Documentation
- **Project Overview**: `docs/PROJECT_OVERVIEW.md`
- **API Reference**: `docs/API_REFERENCE.md`
- **Quick Start**: `docs/QUICK_START.md`

### Issues
- Check existing documentation first
- Review AI Foreman logs
- Create issue with detailed description
- Include relevant log files

---

**Built with ❤️ and AI Foreman for CVExcel**
