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
    ForEach-Object { $_.ToString("x2") } | Join-String
}

$fp = Get-RepoFingerprint
$fpPath = ".ai\state\fp.json"
$prior = if (Test-Path $fpPath) { (Get-Content $fpPath | ConvertFrom-Json).fingerprint } else { "" }

if ($fp -eq $prior) { Write-Host "No-op: fingerprint unchanged"; exit 0 }

# Checks
pwsh .ai\checks\extract_api.ps1
pwsh .ai\checks\find_dead_links.ps1
pwsh .ai\checks\comment_vs_impl.ps1
pwsh .ai\checks\cursor_chat_monitor.ps1
pwsh .ai\checks\vendor_module_analysis.ps1
pwsh .ai\checks\security_audit.ps1

# Plans
$planDocs = pwsh .ai\planners\plan_docs_sync.ps1 -ApiJson .ai\state\api.json
$planDead = pwsh .ai\planners\plan_fix_dead_links.ps1 -Report .ai\state\deadlinks.json
$planComm = pwsh .ai\planners\plan_comment_updates.ps1 -Report .ai\state\comments.json
$planCursor = pwsh .ai\planners\plan_cursor_chat_changes.ps1 -Request .ai\state\cursor-request.json
$planVendor = pwsh .ai\planners\plan_vendor_improvements.ps1 -Analysis .ai\state\vendor-analysis.json
$planSecurity = pwsh .ai\planners\plan_security_fixes.ps1 -Audit .ai\state\security-audit.json

$plans = @($planDocs, $planDead, $planComm, $planCursor, $planVendor, $planSecurity) | Where-Object { $_ -and $_ -ne "NOOP" }
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
