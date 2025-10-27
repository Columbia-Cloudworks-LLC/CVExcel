# Cursor Native Development

## Migration from AI Foreman to Cursor Native AI

This document outlines the migration from PowerShell-based AI Foreman scripts to Cursor's native AI capabilities.

## Why Cursor Native AI?

**Cursor-First Development Philosophy**: All AI-driven development now happens directly through Cursor's chat interface, eliminating the need for PowerShell-based automation scripts.

### Key Benefits

- **Simpler Workflow**: No need to invoke PowerShell scripts for AI-driven development
- **Direct Integration**: Changes happen in real-time through Cursor chat
- **Idempotent by Default**: Cursor handles change application automatically
- **Better UX**: Natural language development requests in chat
- **No Script Maintenance**: Eliminates the need to maintain PowerShell AI automation scripts

## What's Been Deprecated

The following PowerShell scripts are **deprecated** and should **NOT** be used:

- ❌ `ai-foreman.ps1` - AI Foreman automation script
- ❌ `cursor-chat-integration.ps1` - Cursor integration wrapper
- ❌ `.ai/` directory - AI Foreman configuration and state

These files have been **deleted** from the repository.

## New Development Workflow

### 1. Using Cursor Chat

Simply open Cursor chat and describe what you want to do:

**Example:**
```
"Add support for Oracle security advisories in the vendor modules"
```

Cursor will:
1. Analyze the codebase
2. Plan the changes
3. Implement the changes
4. Make edits directly to files
5. Review changes before committing

### 2. Making Code Changes

Instead of running PowerShell scripts:

**Old Way (Deprecated):**
```powershell
.\cursor-chat-integration.ps1 -Type "add_feature" -Description "Add Oracle vendor module"
```

**New Way (Cursor Native):**
Just type in Cursor chat:
```
"Add a new OracleVendor.ps1 module that inherits from BaseVendor.ps1"
```

### 3. Testing and Validation

Run tests manually after Cursor makes changes:

```powershell
# Run all tests
pwsh ./tests/run-all-tests.ps1

# Run specific vendor tests
pwsh ./tests/test-vendor-integration.ps1

# Run PSScriptAnalyzer
Invoke-ScriptAnalyzer -Path vendors/ -Recurse
```

### 4. Code Review and Commit

Review the changes made by Cursor:
1. Check the file diffs in Cursor
2. Run tests to verify functionality
3. Commit changes when ready

## Project Specifications

All project specifications are now maintained in:
- `.cursorrules` - Cursor workspace rules and guidelines
- `spec-kit.yaml` - Comprehensive project specifications
- `cursor-workspace.json` - Workspace metadata

These files guide Cursor's AI behavior instead of PowerShell scripts.

## Migration Checklist

- [x] Updated `.cursorrules` to remove AI Foreman references
- [x] Updated `cursor-workspace.json` to reflect Cursor-native workflow
- [x] Added `.ai/` to `.gitignore`
- [x] Created this migration guide
- [x] Deleted AI Foreman scripts (ai-foreman.ps1, cursor-chat-integration.ps1, Init-AIForeman.ps1)
- [x] Removed AI Foreman documentation (AI_FOREMAN_INTEGRATION.md, AI_FOREMAN_LOG.md)
- [x] Updated README.md and spec-kit.yaml to remove AI Foreman references

## Key Principles

1. **No PowerShell Scripts for AI**: All AI-driven development happens in Cursor chat
2. **Direct Code Changes**: Cursor implements changes directly, no intermediate scripts
3. **Natural Language**: Describe what you want in plain English
4. **Idempotent Changes**: Cursor handles change application automatically
5. **Security First**: All code follows NIST security guidelines (still enforced)

## Getting Help

- Review `.cursorrules` for project guidelines
- Check `spec-kit.yaml` for detailed specifications
- Use Cursor chat for any development tasks
- Run tests to verify changes

## What Stays the Same

- **NIST Security Guidelines**: Still enforced through `.cursorrules`
- **PowerShell Best Practices**: Still followed
- **Playwright Integration**: Still used for web scraping
- **Vendor Modules**: Still modular and inherit from BaseVendor
- **Testing**: Still uses Pester and Playwright
- **Documentation**: Still comprehensive and required

## Examples

### Adding a New Vendor Module

**Cursor Chat:**
```
"I need to add a new vendor module for Red Hat. It should inherit from BaseVendor.ps1
and implement the required methods: Get-VendorName(), Invoke-VendorScraping(),
Test-VendorModule(), and Get-VendorMetadata()."
```

Cursor will create `vendors/RedHatVendor.ps1` with all required methods.

### Fixing a Bug

**Cursor Chat:**
```
"The Microsoft vendor scraping is failing for the new MSRC page layout.
Please update MicrosoftVendor.ps1 to handle the new page structure."
```

Cursor will analyze and fix the issue.

### Security Improvements

**Cursor Chat:**
```
"Add input validation to all vendor modules to prevent injection attacks.
Follow NIST security guidelines for all input parameters."
```

Cursor will add proper input validation across all vendor modules.

## FAQ

**Q: Can I still use the old AI Foreman scripts?**
A: No, they are deprecated and excluded from version control.

**Q: What if I need automation beyond Cursor chat?**
A: Use standard PowerShell scripts for non-AI tasks (e.g., build scripts, deployment, testing).

**Q: Does Cursor support all the same features as AI Foreman?**
A: Yes, Cursor's native AI provides all the same capabilities through its chat interface.

**Q: How do I track changes made by Cursor?**
A: Use git to commit and review changes. Cursor shows diffs before applying changes.

**Q: What about the .ai/ directory?**
A: It's been deleted. AI development should only live in `.cursor` and `.spec` directories.

## Conclusion

The migration to Cursor-native AI development simplifies the workflow while maintaining all functionality. Development is now more intuitive and doesn't require invoking PowerShell scripts for AI-driven tasks.
