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
