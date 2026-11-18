# Cangmo test suite
# Node 18+ required. Start the server on the matching port first.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$base = if ($env:CANGMO_BASE) { $env:CANGMO_BASE } else { "http://127.0.0.1:18085" }
$env:CANGMO_BASE = $base
$node = (Get-Command node).Source

Write-Host "== unit tests =="
Push-Location $root
cjpm test
Pop-Location

Write-Host "== smoke =="
& $node "$root\tests\smoke.mjs"

Write-Host "== e2e =="
& $node "$root\tests\e2e.mjs"

Write-Host "== extended =="
& $node "$root\tests\extended.mjs"

Write-Host "== v1.0.1 =="
& $node "$root\tests\v101.mjs"

Write-Host "== load =="
& $node "$root\tests\load.mjs"

Write-Host "== security =="
& $node "$root\tests\security.mjs"
