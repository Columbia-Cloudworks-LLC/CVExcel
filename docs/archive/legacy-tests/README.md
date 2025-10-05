# Legacy Test Files Archive

**Date Archived**: October 5, 2025
**Archived By**: Phase 1 Tech Debt Reduction
**Reason**: These files are legacy/unmaintained test scripts

---

## Archived Files

### CVScrape-legacy.ps1 (1,110 lines)
- Original CVScrape implementation
- Superseded by modular vendor architecture
- Kept for historical reference

### CVScrape.ps1 (837 lines)
- Intermediate refactoring of CVScrape
- Superseded by CVExcel unified GUI
- Contains working scraping logic that was migrated to vendors

### CVScrape-Refactored.ps1 (600 lines)
- Further refactored version
- Served as prototype for current architecture
- Code patterns migrated to ui/ScrapingEngine.ps1

---

## Why Archived?

These files were moved to archive during Phase 1 technical debt reduction:

1. **No longer maintained**: Not updated since unified GUI implementation
2. **Functionality preserved**: Core logic migrated to:
   - `vendors/` - Vendor-specific scraping modules
   - `ui/ScrapingEngine.ps1` - Unified scraping engine
   - `ui/CVExcel-GUI.ps1` - Unified GUI interface
3. **Reduce clutter**: Simplify active codebase
4. **Historical value**: Keep for reference and learning

---

## If You Need These Files

These files are preserved for:
- Understanding evolution of the codebase
- Reference implementation details
- Comparing old vs new approaches
- Educational purposes

**Do NOT use these files for new development** - they are outdated.

Use the current implementation in:
- `ui/CVExcel-GUI.ps1` - Main GUI
- `vendors/` - Vendor modules
- `ui/ScrapingEngine.ps1` - Scraping engine

---

## Git History

Full git history is preserved if you need to see the original context where these files were active.
