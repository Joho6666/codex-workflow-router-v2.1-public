param(
[string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }),
    [string]$ConfigPath = '',
    [string]$RuntimeToolsPath = '',
    [string]$OutputPath = '',
    [int]$StaleAfterSeconds = 21600,
    [switch]$SkipRuntimeToolsUpdate
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Output 'PowerShell 7+ required. Run this script with pwsh.exe.'
    exit 64
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $CodexHome 'config.toml' }
if ([string]::IsNullOrWhiteSpace($RuntimeToolsPath)) { $RuntimeToolsPath = Join-Path $CodexHome 'RUNTIME_TOOLS.json' }
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $CodexHome 'MCP_RUNTIME_STATUS.json' }

. (Join-Path $PSScriptRoot 'workflow-router-core.ps1')
$catalog = Get-WorkflowRouterCatalog -CatalogPath (Join-Path $CodexHome 'ROUTING_CATALOG.json')
$servers = @(Get-ConfiguredMcpNames -ConfigPath $ConfigPath)
$runtime = $null
if (Test-Path -LiteralPath $RuntimeToolsPath -PathType Leaf) { $runtime = Read-WorkflowRouterJson -Path $RuntimeToolsPath }
$observedAt = (Get-Date).ToUniversalTime().ToString('o')
$snapshotId = [guid]::NewGuid().ToString()
$runtimeTools = if ($null -ne $runtime) { @($runtime.tools) } else { @() }
$runtimeObservedAt = $null
if ($null -ne $runtime) {
    if ($runtime.PSObject.Properties.Name -contains 'observed_at') { $runtimeObservedAt = [string]$runtime.observed_at }
    elseif ($runtime.PSObject.Properties.Name -contains 'generated_at') { $runtimeObservedAt = [string]$runtime.generated_at }
    if ([string]::IsNullOrWhiteSpace($runtimeObservedAt)) { $runtimeObservedAt = $observedAt }
}
$runtimeIsFresh = ($null -ne $runtime -and -not (Test-RouteSnapshotStale -Snapshot $runtime -ObservedAt $runtimeObservedAt -DefaultSeconds $StaleAfterSeconds))
$serverRecords = New-Object System.Collections.Generic.List[object]
foreach ($server in $servers) {
    $namespacePattern = '(?i)^mcp__' + [regex]::Escape($server) + '(?:__|_)'
    $matchingTools = if ($runtimeIsFresh) { @($runtimeTools | Where-Object { [string]$_.name -match $namespacePattern }) } else { @() }
    $runtimeVisible = if ($matchingTools.Count -gt 0) { $true } else { $null }
    $toolsDiscovered = if ($matchingTools.Count -gt 0) { $true } else { $null }
    $evidence = New-Object System.Collections.Generic.List[string]
    $evidence.Add('configured from config.toml')
    if ($matchingTools.Count -gt 0) { $evidence.Add("runtime tool inventory matched $($matchingTools.Count) tool(s)") }
    elseif ($null -eq $runtime) { $evidence.Add('runtime tool inventory was unavailable; state remains unknown') }
    else { $evidence.Add('runtime tool inventory is stale; state remains unknown') }
    $serverRecords.Add([ordered]@{
        server=$server
        configured=$true
        runtime_visible=$runtimeVisible
        tools_discovered=$toolsDiscovered
        runtime_available=$null
        healthy=$null
        startable=$null
        reachable=$null
        connected=$null
        observed_at=$observedAt
        snapshot_id=$snapshotId
        stale=$false
        evidence=@($evidence)
    })
}
$snapshot = [ordered]@{
    schema_version='2.1'
    snapshot_id=$snapshotId
    observed_at=$observedAt
    stale_after_seconds=$StaleAfterSeconds
    stale=$false
    source=@('config.toml', 'RUNTIME_TOOLS.json')
    servers=$serverRecords.ToArray()
}
$json = $snapshot | ConvertTo-Json -Depth 20
Write-RouteAtomicText -Path $OutputPath -Content $json

if ($null -ne $runtime -and -not $SkipRuntimeToolsUpdate) {
    $runtimeMeta = [ordered]@{}
    foreach ($property in $runtime.PSObject.Properties) { $runtimeMeta[$property.Name] = $property.Value }
    $runtimeMeta.observed_at = $runtimeObservedAt
    $seed = "runtime-tools|$($runtimeMeta.source)|$($runtimeMeta.generated_at)|$($runtimeMeta.tool_count)"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $runtimeHash = ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($seed)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    $runtimeMeta.schema_version = '2.1'
    $runtimeMeta.snapshot_id = "runtime-$($runtimeHash.Substring(0, 16))"
    $runtimeMeta.stale_after_seconds = $StaleAfterSeconds
    $runtimeMeta.stale = Test-RouteSnapshotStale -Snapshot $runtimeMeta -ObservedAt $runtimeObservedAt -DefaultSeconds $StaleAfterSeconds
    $runtimeJson = $runtimeMeta | ConvertTo-Json -Depth 20
    Write-RouteAtomicText -Path $RuntimeToolsPath -Content $runtimeJson
    Write-Output "RUNTIME TOOLS METADATA UPDATED: $RuntimeToolsPath"
}
Write-Output "MCP RUNTIME SNAPSHOT UPDATED: $OutputPath"
Write-Output "  SERVERS: $($servers.Count), HEALTH_ASSERTIONS: none (healthy remains null without explicit probe evidence)"
