# Assembles the local git repo that Multiroptcg pulls its OPTCG data from:
# scripts (base runtime + card scripts), the card database and the Win32
# ocgcore.dll, all taken from the canonical EDOPCG build. Re-run after any
# canon change, then restart multirole (or hit the webhook) to pick it up.
param(
    [string]$Canon = 'F:\edopcg_CODEX_INTEGRATED_20260701_FINAL_EDIT_BY_CLAUDE_FABLE\bin\release',
    [string]$DataRepo = 'E:\Multiroptcg-data'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath (Join-Path $Canon 'ocgcore.dll'))) {
    throw "canon release not found: $Canon"
}

New-Item -ItemType Directory -Force -Path $DataRepo | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $DataRepo 'script') | Out-Null

# Base engine scripts (constant.lua, utility.lua chain-loads opcg_bootstrap.lua)
Copy-Item -Path (Join-Path $Canon 'script\*.lua') -Destination (Join-Path $DataRepo 'script') -Force
# OPCG runtime + every card script. Later copies win name collisions on the
# provider side, but keep a single source of truth anyway.
Copy-Item -Path (Join-Path $Canon 'expansions\script\*.lua') -Destination (Join-Path $DataRepo 'script') -Force
# Card database and the core the rooms will load.
Copy-Item -LiteralPath (Join-Path $Canon 'expansions\cards-opcg.cdb') -Destination $DataRepo -Force
Copy-Item -LiteralPath (Join-Path $Canon 'ocgcore.dll') -Destination $DataRepo -Force

Push-Location $DataRepo
try {
    if (-not (Test-Path -LiteralPath '.git')) {
        git init | Out-Null
        git config user.name 'optcg-packer'
        git config user.email 'optcg-packer@local'
    }
    git add -A
    $pending = git status --porcelain
    if ($pending) {
        git commit -m "pack optcg data $(Get-Date -Format 'yyyy-MM-dd HH:mm')" | Out-Null
        Write-Host "committed: $((git rev-parse --short HEAD))"
        # hot-reload a running server (no-op if it is offline; next boot applies)
        try {
            Invoke-WebRequest -Uri 'http://127.0.0.1:34343/' -Method Post -Body 'optcg-drop-apply' -TimeoutSec 3 -UseBasicParsing | Out-Null
            Write-Host 'server hot-reloaded'
        } catch {
            Write-Host 'server offline - picked up on next start'
        }
    } else {
        Write-Host 'no changes to commit'
    }
}
finally {
    Pop-Location
}
Write-Host "data repo ready: $DataRepo"
