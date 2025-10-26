# save as tools\Init-AIForeman.ps1 and run: pwsh tools\Init-AIForeman.ps1
$ErrorActionPreference = "Stop"

$paths = @(
    ".ai", ".ai\prompts", ".ai\checks", ".ai\planners", ".ai\state",
    ".github\workflows", "docs", "tools"
)
$paths | ForEach-Object { if (-not (Test-Path $_)) { New-Item -ItemType Directory $_ | Out-Null } }

# --- Spec Pack (pinned behavior; prevents drift) ---
@'
version: 1
pack_id: "cvexcel/ai-foreman@1.0.0"
models:
  primary: "gpt-5-thinking@2025-10"
  reviewer: "gpt-4o-mini@2025-08"
determinism:
  seed: 42
  temperature: 0.0
  max_tokens: 2000
policies:
  no_op_if_benefit_score_below: 0.65
  require_green_tests: true
  require_changed_lines_min: 3
  max_changed_lines: 400
  safe_file_globs:
    - "**/*.md"
    - "**/*.ps1"
    - "**/*.psm1"
    - "**/*.cs"
    - "**/*.ts"
truth_sources:
  - "build"
  - "tests"
  - "api-introspection"
  - "linters"
  - "docs"
outputs:
  pr_title_template: "[AI Foreman] {category}: {short_reason}"
  branch_prefix: "chore/ai-foreman/"
attestations:
  write_sarif: ".ai/last-run.sarif"
  write_fingerprint: ".ai/state/fp.json"
'@ | Set-Content .ai\spec-pack.yaml -Encoding UTF8

# --- Declarative rules (what to check & how to judge) ---
@'
rules:
  - id: docs-sync-api
    category: "documentation"
    description: "Ensure README/API docs reflect exported public commands."
    check: { run: "pwsh .ai/checks/extract_api.ps1" }
    plan:  { run: "pwsh .ai/planners/plan_docs_sync.ps1 -ApiJson .ai/state/api.json" }
    judgment_tests:
      - "pwsh ./build.ps1"
      - "pwsh ./test.ps1"
      - "pwsh ./lint.ps1"
    acceptance:
      require_benefit_score_min: 0.70

  - id: dead-links
    category: "hygiene"
    check: { run: "pwsh .ai/checks/find_dead_links.ps1" }
    plan:  { run: "pwsh .ai/planners/plan_fix_dead_links.ps1 -Report .ai/state/deadlinks.json" }
    judgment_tests:
      - "pwsh ./build.ps1"
    acceptance:
      require_benefit_score_min: 0.65

  - id: comment-accuracy-vs-code
    category: "documentation"
    check: { run: "pwsh .ai/checks/comment_vs_impl.ps1" }
    plan:  { run: "pwsh .ai/planners/plan_comment_updates.ps1 -Report .ai/state/comments.json" }
    acceptance:
      require_benefit_score_min: 0.70
'@ | Set-Content .ai\rules.yaml -Encoding UTF8

# --- Prompts (templates used by planners; version them) ---
@'
# Prompt: docs_sync v1.0.0
# Inputs: api.json, README.md excerpts
# Output: unified diff; do not editorialize; only minimal changes to sync facts.
You are a change planner. Produce a concise unified diff that updates README.md
so that exported public commands, parameters, and examples exactly match api.json.
- Do not touch unrelated sections.
- Keep voice/tone exactly as-is.
- Prefer additions over deletions when clarifying.
- If no meaningful change is needed, output: NOOP
'@ | Set-Content .ai\prompts\docs_sync.txt -Encoding UTF8

@'
# Prompt: dead_links v1.0.0
Given a JSON array of broken links with files/lines, produce a unified diff
that fixes or removes the links with the least invasive change. If a link
is important but the target is truly gone, add a short footnote "(reference archived)"
and point to the Wayback snapshot if available.
If zero fixes are meaningful, output: NOOP
'@ | Set-Content .ai\prompts\dead_links.txt -Encoding UTF8

@'
# Prompt: comments_vs_impl v1.0.0
Given a report of mismatches between comments and implementation, produce a unified
diff that updates only the incorrect comments. Do not reflow or restyle large blocks.
If changes are trivial (<3 lines total), output NOOP.
'@ | Set-Content .ai\prompts\comments_vs_impl.txt -Encoding UTF8

# --- Deterministic checks (no LLM calls) ---
@'
# outputs .ai/state/api.json describing public PS functions (name + parameters)
$ErrorActionPreference = "SilentlyContinue"
$cmds = Get-ChildItem -Recurse -Filter *.psm1 | ForEach-Object {
  try {
    $m = Import-Module $_.FullName -PassThru
    if ($m) {
      Get-Command -Module $m.Name -CommandType Function |
        Select-Object Name, @{n="Parameters";e={$_.Parameters.Keys}}
    }
  } catch {}
}
$cmds | ConvertTo-Json -Depth 6 | Set-Content .ai\state\api.json -Encoding UTF8
'@ | Set-Content .ai\checks\extract_api.ps1 -Encoding UTF8

@'
# scans *.md for dead links → .ai/state/deadlinks.json
$md = Get-ChildItem -Recurse -Include *.md
$dead = @()
foreach ($f in $md) {
  $i=0
  foreach ($line in Get-Content $f.FullName) {
    $i++
    if ($line -match "\[([^\]]+)\]\((http[^\)]+)\)") {
      $url = $Matches[2]
      try {
        $resp = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec 8 -ErrorAction Stop
        if ($resp.StatusCode -ge 400) { $dead += [pscustomobject]@{file=$f.FullName; line=$i; url=$url; code=$resp.StatusCode} }
      } catch { $dead += [pscustomobject]@{file=$f.FullName; line=$i; url=$url; code="error"} }
    }
  }
}
$dead | ConvertTo-Json | Set-Content .ai\state\deadlinks.json -Encoding UTF8
'@ | Set-Content .ai\checks\find_dead_links.ps1 -Encoding UTF8

@'
# VERY simple heuristic: flag comments that mention parameter names not present in the function
# → .ai/state/comments.json
$report = @()
Get-ChildItem -Recurse -Filter *.ps1,*.psm1 | ForEach-Object {
  $text = Get-Content $_.FullName -Raw
  $comments = ($text -split "`n") | Where-Object { $_ -match "^\s*#"}
  if ($comments.Count -eq 0) { return }
  # naive token extraction
  $params = Select-String -InputObject $text -Pattern "param\s*\((.+?)\)" -AllMatches |
            ForEach-Object { $_.Matches.Groups[1].Value } | Out-String
  foreach ($c in $comments) {
    if ($params -and $c -match "\-(\w+)" -and ($params -notmatch $Matches[1])) {
      $report += [pscustomobject]@{file=$_.FullName; comment=$c.Trim(); issue="mentions unknown parameter"}
    }
  }
}
$report | ConvertTo-Json -Depth 6 | Set-Content .ai\state\comments.json -Encoding UTF8
'@ | Set-Content .ai\checks\comment_vs_impl.ps1 -Encoding UTF8

# --- Planners (LLM-mediated diffs; stubs call your LLM locally or via CLI you choose) ---
@'
param([string]$ApiJson)
# Read API facts and README, then call your LLM (implementation-specific) with prompts\docs_sync.txt
# For now, emit NOOP so the pipeline is runnable without keys.
"NOOP"
'@ | Set-Content .ai\planners\plan_docs_sync.ps1 -Encoding UTF8

@'
param([string]$Report)
"NOOP"
'@ | Set-Content .ai\planners\plan_fix_dead_links.ps1 -Encoding UTF8

@'
param([string]$Report)
"NOOP"
'@ | Set-Content .ai\planners\plan_comment_updates.ps1 -Encoding UTF8

# --- Orchestrator (local & CI entrypoint) ---
@'
param([switch]$VerboseLog)

function Get-Pack() { Get-Content .ai\spec-pack.yaml -Raw | ConvertFrom-Yaml }

function Get-RepoFingerprint {
  $hash = @(
    (git rev-parse HEAD).Trim(),
    (Get-FileHash .ai\spec-pack.yaml -Algorithm SHA256).Hash,
    (Get-FileHash .ai\rules.yaml -Algorithm SHA256).Hash
  ) -join ":"
  $bytes = [Text.Encoding]::UTF8.GetBytes($hash)
  (New-Object -TypeName System.Security.Cryptography.SHA256Managed).ComputeHash($bytes) |
    ForEach-Object ToString x2 | ForEach-Object { $_ } -join ""
}

$fp = Get-RepoFingerprint
$fpPath = ".ai\state\fp.json"
$prior = if (Test-Path $fpPath) { (Get-Content $fpPath | ConvertFrom-Json).fingerprint } else { "" }

if ($fp -eq $prior) { Write-Host "No-op: fingerprint unchanged"; exit 0 }

# Checks
pwsh .ai\checks\extract_api.ps1
pwsh .ai\checks\find_dead_links.ps1
pwsh .ai\checks\comment_vs_impl.ps1

# Plans
$planDocs = pwsh .ai\planners\plan_docs_sync.ps1 -ApiJson .ai\state\api.json
$planDead = pwsh .ai\planners\plan_fix_dead_links.ps1 -Report .ai\state\deadlinks.json
$planComm = pwsh .ai\planners\plan_comment_updates.ps1 -Report .ai\state\comments.json

$plans = @($planDocs, $planDead, $planComm) | Where-Object { $_ -and $_ -ne "NOOP" }
if ($plans.Count -eq 0) {
  Write-Host "No-op: planners returned NOOP"
  @{ fingerprint = $fp; when = (Get-Date).ToString("s") } | ConvertTo-Json | Set-Content $fpPath
  exit 0
}

# (Minimal apply stub) Expect unified diffs; apply, test, and revert on failure.
$branch = "chore/ai-foreman/{0:yyyyMMddHHmm}" -f (Get-Date)
git checkout -b $branch
$applied = $false
foreach ($p in $plans) {
  if ($p -match "^\s*diff\s") {
    $p | Out-File .ai\state\patch.diff -Encoding ascii
    git apply --whitespace=fix .ai\state\patch.diff
    $applied = $true
  }
}
if (-not $applied) {
  Write-Host "No-op: no diffs to apply"
  git checkout - 2>$null
  git branch -D $branch 2>$null
  @{ fingerprint = $fp; when = (Get-Date).ToString("s") } | ConvertTo-Json | Set-Content $fpPath
  exit 0
}

# Judgment tests (best-effort; tolerate missing scripts)
function Try-Run($cmd) {
  Write-Host "→ $cmd"
  try { Invoke-Expression $cmd; return $LASTEXITCODE } catch { return 1 }
}
$tests = @("pwsh ./build.ps1","pwsh ./test.ps1","pwsh ./lint.ps1")
foreach ($t in $tests) { if ((Test-Path ($t -replace 'pwsh ','' -replace ' ./','')) -and (Try-Run $t)) { git reset --hard; git checkout -; git branch -D $branch; exit 0 } }

# Commit + PR body & lessons learned tick
git add -A
git commit -m "[AI Foreman] alignment updates"
git push -u origin $branch

# Lessons log tick
$ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
"[$ts] AI Foreman: proposed alignment update on branch $branch" | Add-Content docs\AI_FOREMAN_LOG.md

# Update fingerprint post-success
@{ fingerprint = $fp; when = (Get-Date).ToString("s") } | ConvertTo-Json | Set-Content $fpPath
'@ | Set-Content ai-foreman.ps1 -Encoding UTF8

# --- CI Workflow (runs safely; no-ops if nothing to do) ---
@'
name: AI Foreman
on:
  workflow_dispatch: {}
  schedule:
    - cron: "0 12 * * 1-5"   # 12:00 UTC weekdays
jobs:
  run:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup PowerShell 7
        uses: PowerShell/PowerShell@v1
        with: { version: "7.4.x" }
      - name: Run AI Foreman
        shell: pwsh
        run: ./ai-foreman.ps1
      - name: Upload SARIF (stub)
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with: { sarif_file: .ai/last-run.sarif }
'@ | Set-Content .github\workflows\ai-foreman.yml -Encoding UTF8

# --- Lessons Learned log (append-only) ---
if (-not (Test-Path docs\AI_FOREMAN_LOG.md)) {
    @'
# AI Foreman – Lessons Learned (Append-Only)

> A running, time-stamped log of what we learned, when, and why decisions were made.
> Only the AI Foreman or maintainers may append. Edits to history are forbidden.

'@ | Set-Content docs\AI_FOREMAN_LOG.md -Encoding UTF8
}

Write-Host "Bootstrap complete. Next steps:"
Write-Host "1) Review .ai/spec-pack.yaml thresholds."
Write-Host "2) Implement your LLM call inside planners/* to replace the NOOP stubs."
Write-Host "3) Commit & push; enable the workflow if desired."
