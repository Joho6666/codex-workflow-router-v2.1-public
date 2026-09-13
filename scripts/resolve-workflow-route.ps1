param(
[string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }),
    [Parameter(Mandatory=$true)][string]$Prompt,
    [string]$CatalogPath = '',
    [string]$FullIndexPath = '',
    [switch]$Explain
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Output 'PowerShell 7+ required. Run this script with pwsh.exe.'
    exit 64
}

if ([string]::IsNullOrWhiteSpace($CatalogPath)) { $CatalogPath = Join-Path $CodexHome 'ROUTING_CATALOG.json' }
if ([string]::IsNullOrWhiteSpace($FullIndexPath)) { $FullIndexPath = Join-Path $CodexHome 'CAPABILITIES_FULL.json' }

. (Join-Path $PSScriptRoot 'workflow-router-core.ps1')
$catalog = Get-WorkflowRouterCatalog -CatalogPath $CatalogPath
$full = Read-WorkflowRouterJson -Path $FullIndexPath
$decision = Get-WorkflowRouteDecision -Prompt $Prompt -Catalog $catalog -Entries @($full.entries)

if ($Explain) {
    Write-Output 'ROUTING_DECISION'
}
$decision | ConvertTo-Json -Depth 30
exit 0
