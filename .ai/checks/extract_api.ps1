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
