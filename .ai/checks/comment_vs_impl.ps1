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
