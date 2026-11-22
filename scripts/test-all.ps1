# Cangmo test suite
# Node 18+ required. Start the server on the matching port first.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$base = if ($env:CANGMO_BASE) { $env:CANGMO_BASE } else { "http://127.0.0.1:18085" }
$env:CANGMO_BASE = $base
if (-not $env:CANGMO_BACKUP_PASSPHRASE) { $env:CANGMO_BACKUP_PASSPHRASE = "test-backup-passphrase-2026" }
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

Write-Host "== v1.1 features =="
& $node "$root\tests\v110.mjs"

Write-Host "== v1.2 features =="
& $node "$root\tests\v120.mjs"

Write-Host "== v1.2.1 token =="
& $node "$root\tests\v121-token.mjs"

Write-Host "== v1.2.1 search/bulk =="
& $node "$root\tests\v121-search.mjs"

Write-Host "== v1.2.1 crypto/variant =="
& $node "$root\tests\v121-crypto.mjs"

Write-Host "== load =="
& $node "$root\tests\load.mjs"

Write-Host "== security =="
& $node "$root\tests\security.mjs"

Write-Host "== v1.3 settings/theme =="
& $node "$root\tests\v130.mjs"
