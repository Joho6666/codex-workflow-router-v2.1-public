param(
[string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }),
    [string]$CatalogPath = '',
    [string]$FullIndexPath = '',
    [string]$SummaryIndexPath = '',
    [string]$McpSnapshotPath = '',
    [string]$RuntimeToolsPath = '',
    [string]$TestResultPath = '',
    [string]$BeforeSummaryPath = '',
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Output 'PowerShell 7+ required. Run this script with pwsh.exe.'
    exit 64
}

if ([string]::IsNullOrWhiteSpace($CatalogPath)) { $CatalogPath = Join-Path $CodexHome 'ROUTING_CATALOG.json' }
if ([string]::IsNullOrWhiteSpace($FullIndexPath)) { $FullIndexPath = Join-Path $CodexHome 'CAPABILITIES_FULL.json' }
if ([string]::IsNullOrWhiteSpace($SummaryIndexPath)) { $SummaryIndexPath = Join-Path $CodexHome 'CAPABILITIES_SUMMARY.json' }
if ([string]::IsNullOrWhiteSpace($McpSnapshotPath)) { $McpSnapshotPath = Join-Path $CodexHome 'MCP_RUNTIME_STATUS.json' }
if ([string]::IsNullOrWhiteSpace($RuntimeToolsPath)) { $RuntimeToolsPath = Join-Path $CodexHome 'RUNTIME_TOOLS.json' }
if ([string]::IsNullOrWhiteSpace($TestResultPath)) { $TestResultPath = Join-Path $CodexHome 'WORKFLOW_ROUTER_V2_1_TEST_RESULTS.json' }
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $CodexHome 'WORKFLOW_ROUTER_V2_1_REPORT.md' }

. (Join-Path $PSScriptRoot 'workflow-router-core.ps1')
$catalog = Get-WorkflowRouterCatalog -CatalogPath $CatalogPath
$full = Read-WorkflowRouterJson -Path $FullIndexPath
$summary = Read-WorkflowRouterJson -Path $SummaryIndexPath
$snapshot = if (Test-Path -LiteralPath $McpSnapshotPath -PathType Leaf) { Read-WorkflowRouterJson -Path $McpSnapshotPath } else { $null }
$runtime = if (Test-Path -LiteralPath $RuntimeToolsPath -PathType Leaf) { Read-WorkflowRouterJson -Path $RuntimeToolsPath } else { $null }
$tests = if (Test-Path -LiteralPath $TestResultPath -PathType Leaf) { Read-WorkflowRouterJson -Path $TestResultPath } else { $null }

function Format-JsonValue {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return ([string]$Value).ToLowerInvariant() }
    return [string]$Value
}

function Get-BeforeSummary {
    param([string]$ExplicitPath, [string]$Root)
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath) -and (Test-Path -LiteralPath $ExplicitPath -PathType Leaf)) { return $ExplicitPath }
    $backupRoot = Join-Path $Root 'backups'
    $candidate = @(Get-ChildItem -LiteralPath $backupRoot -Directory -Filter 'workflow-router-v2.1-p0-*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'CAPABILITIES_SUMMARY.json' } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }) | Select-Object -First 1
    return [string]$candidate
}

function Get-ProfileNames {
    param($Profile)
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($field in @('primary_skill_candidates','supporting_skill_candidates','verification_candidates','primary_candidates','supporting_candidates','verification')) {
        foreach ($name in @(ConvertTo-RouteStringArray $Profile.$field)) { $names.Add($name) }
    }
    return @($names | Select-Object -Unique)
}

function Get-ProfileDiff {
    param($Before, $After, [string]$ProfileName)
    $old = if ($null -ne $Before -and $null -ne $Before.profiles.PSObject.Properties[$ProfileName]) { Get-ProfileNames $Before.profiles.$ProfileName } else { @() }
    $new = if ($null -ne $After -and $null -ne $After.profiles.PSObject.Properties[$ProfileName]) { Get-ProfileNames $After.profiles.$ProfileName } else { @() }
    return [pscustomobject]@{ added=@($new | Where-Object { $old -notcontains $_ }); removed=@($old | Where-Object { $new -notcontains $_ }); before=@($old); after=@($new) }
}

function Get-SkillQaRows {
    param($FullIndex, $Catalog)
    $skillEntries = @($FullIndex.entries | Where-Object kind -eq 'skill')
    $required = @($Catalog.qa_rules.required_sample_skills)
    $requiredEntries = New-Object System.Collections.Generic.List[string]
    foreach ($name in $required) { if (-not ($requiredEntries -contains $name)) { $requiredEntries.Add($name) } }
    $random = @($skillEntries | ForEach-Object {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { $key=([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes([string]$_.name)))).Replace('-', '') }
        finally { $sha.Dispose() }
        [pscustomobject]@{ name=$_.name; key=$key }
    } | Sort-Object key | Select-Object -First ([int]$Catalog.qa_rules.minimum_random_sample) | ForEach-Object name)
    $names = @($requiredEntries + $random | Select-Object -Unique)
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($name in $names) {
        $entry = @($skillEntries | Where-Object name -eq $name | Sort-Object @{Expression='source_runtime';Descending=$false}) | Select-Object -First 1
        if ($null -eq $entry) {
            $rows.Add([pscustomobject]@{ name=$name; status='UNKNOWN'; reason='skill not found in current Full Index' })
            continue
        }
        $status = if ($entry.source_runtime -eq 'codex' -and @($entry.capabilities).Count -gt 0) { 'CORRECT' } elseif ($entry.source_runtime -eq 'mirasim') { 'ACCEPTABLE' } elseif (@($entry.capabilities).Count -eq 0) { 'UNKNOWN' } else { 'ACCEPTABLE' }
        $reason = "runtime=$($entry.source_runtime); capabilities=$(@($entry.capabilities) -join ','); confidence=$($entry.confidence)"
        $rows.Add([pscustomobject]@{ name=$name; status=$status; reason=$reason })
    }
    return $rows.ToArray()
}

$beforePath = Get-BeforeSummary -ExplicitPath $BeforeSummaryPath -Root $CodexHome
$before = if ($beforePath) { Read-WorkflowRouterJson -Path $beforePath } else { $null }
$diffs = [ordered]@{}
foreach ($profileName in @($summary.profiles.PSObject.Properties.Name)) { $diffs[$profileName] = Get-ProfileDiff -Before $before -After $summary -ProfileName $profileName }
$qaRows = @(Get-SkillQaRows -FullIndex $full -Catalog $catalog)
$referenceRows = @(Test-WorkflowRouterReferenceIntegrity -Catalog $catalog -FullIndex $full -Summary $summary -RouterPath (Join-Path $CodexHome 'WORKFLOW_ROUTER.md'))
$referenceFailures = @($referenceRows | Where-Object status -eq 'FAIL')

$mcpRows = @($full.entries | Where-Object kind -eq 'mcp')
$mcpConfigured = @($mcpRows | Where-Object { $_.availability.configured -eq $true }).Count
$mcpVisible = @($mcpRows | Where-Object { $_.availability.runtime_visible -eq $true }).Count
$mcpHealthy = @($mcpRows | Where-Object { $_.availability.healthy -eq $true }).Count
$mcpStale = @($mcpRows | Where-Object { $_.availability.stale -eq $true }).Count
$mcpUnknown = $mcpRows.Count - $mcpHealthy
$mcpSnapshotStale = ($null -eq $snapshot -or (Test-RouteSnapshotStale -Snapshot $snapshot -ObservedAt ([string]$snapshot.observed_at) -DefaultSeconds ([int]$catalog.runtime_policy.snapshot.stale_after_seconds)))
$runtimeSnapshotStale = ($null -eq $runtime -or (Test-RouteSnapshotStale -Snapshot $runtime -ObservedAt ([string]$runtime.observed_at) -DefaultSeconds ([int]$catalog.runtime_policy.snapshot.stale_after_seconds)))
$configuredMcp = @(Get-ConfiguredMcpNames -ConfigPath (Join-Path $CodexHome 'config.toml'))
$snapshotMcp = @($snapshot.servers | ForEach-Object { [string]$_.server })
$mcpConfigMismatch = ((@(Get-RouteStableUnique -Items $configuredMcp | Sort-Object) -join '|') -ne (@(Get-RouteStableUnique -Items $snapshotMcp | Sort-Object) -join '|'))
$realAgent = if (Test-Path -LiteralPath (Join-Path $CodexHome 'REAL_AGENT_EVAL.json') -PathType Leaf) { Read-WorkflowRouterJson -Path (Join-Path $CodexHome 'REAL_AGENT_EVAL.json') } else { [pscustomobject]@{ status='NOT_RUN'; reason='No real Agent Eval result was supplied.' } }
$contamination = @($full.classification_audit.profile_contamination)
$ready = ($realAgent.status -eq 'PASS' -and $contamination.Count -eq 0 -and $referenceFailures.Count -eq 0 -and $mcpUnknown -eq 0 -and $mcpStale -eq 0 -and -not $mcpSnapshotStale -and -not $runtimeSnapshotStale -and -not $mcpConfigMismatch)
$reportGeneratedAt = (Get-Date).ToUniversalTime().ToString('o')
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# Codex Workflow Router V2.1 Reliability Report')
$lines.Add('')
$lines.Add("Generated: $reportGeneratedAt")
$lines.Add("Index snapshot generated: $($full.generated_at)")
$lines.Add('')
$lines.Add('## A. 修改文件')
$lines.Add('')
$lines.Add('- `AGENTS.md`, `WORKFLOW_ROUTER.md`, `ROUTING_CATALOG.json`')
$lines.Add('- `CAPABILITIES_FULL.json`, `CAPABILITIES_SUMMARY.json`, `CAPABILITIES.json`, `RUNTIME_TOOLS.json`, `MCP_RUNTIME_STATUS.json`')
$lines.Add('- `scripts/workflow-router-core.ps1`, `scripts/resolve-workflow-route.ps1`, `scripts/update-capability-index.ps1`, `scripts/update-mcp-runtime-status.ps1`, `scripts/test-workflow-router.ps1`, `scripts/generate-workflow-router-report.ps1`')
$lines.Add('')
$lines.Add('## B. P0 Bug 修复')
$lines.Add('')
$lines.Add('- Single Routing Catalog is now the machine source of truth.')
$lines.Add('- Intent and domains are separated; Worktree/Subagent are independent gates.')
$lines.Add('- Runtime filtering happens before candidate scoring; stale/unknown runtime is not treated as available.')
$lines.Add('- Profile candidates use contextual roles, score thresholds, stable sorting, and negative evidence.')
$lines.Add('')
$lines.Add('## C. Intent + Domain Schema')
$lines.Add('')
$lines.Add("Intents: $(@($catalog.intents.PSObject.Properties.Name) -join ', ')")
$lines.Add("Domains: $(@($catalog.domains.PSObject.Properties.Name) -join ', ')")
$lines.Add('')
$lines.Add('## D. Contextual Role Schema')
$lines.Add('')
$lines.Add('- Roles are bound by intent/domain/capability context through `routing_roles` and Catalog bindings.')
$lines.Add('- `verification-before-completion` is verification-only; Provider entries cannot be Primary Skills.')
$lines.Add('')
$lines.Add('## E. Candidate Scoring')
$lines.Add('')
$lines.Add(($catalog.candidate_scoring | ConvertTo-Json -Depth 8))
$lines.Add('')
$lines.Add('## F. Runtime Filter')
$lines.Add('')
$lines.Add("Runtime policy: $($catalog.runtime_policy | ConvertTo-Json -Compress -Depth 8)")
$lines.Add("MCP configured/visible/healthy/unknown/stale: $mcpConfigured / $mcpVisible / $mcpHealthy / $mcpUnknown / $mcpStale")
$lines.Add('')
$lines.Add('## G. Tokenizer 修复')
$lines.Add('')
$lines.Add('- Compound tokens retain the original token and add split tokens for exact boundary matching.')
$lines.Add('')
$lines.Add('## H. Trigger Provenance')
$lines.Add('')
$lines.Add("Explicit=$($full.statistics.explicit_trigger_count); Derived=$($full.statistics.derived_trigger_count); Fallback=$($full.statistics.fallback_description_count); Empty=$($full.statistics.empty_trigger_count); ParserFailures=$($full.statistics.description_parser_failure_count)")
$lines.Add('')
$lines.Add('## I. Profile Before / After')
$lines.Add('')
if ($before) { $lines.Add(('Before source: `' + $beforePath + '`')) } else { $lines.Add('Before source: UNAVAILABLE') }
foreach ($profileName in $diffs.Keys) {
    $d = $diffs[$profileName]
    $lines.Add("### $profileName")
    $lines.Add("- Added: $(@($d.added) -join ', ')")
    $lines.Add("- Removed: $(@($d.removed) -join ', ')")
}
$lines.Add('')
$lines.Add('## J. Skill Statistics')
$lines.Add('')
$lines.Add("Skills=$($full.statistics.skill_count); Classified=$($full.statistics.skill_count - $full.statistics.unclassified_count); Unclassified=$($full.statistics.unclassified_count); LowConfidence=$($full.statistics.low_confidence_count)")
$lines.Add('')
$lines.Add('## K. MCP Status')
$lines.Add('')
$lines.Add("Configured=$mcpConfigured; RuntimeVisible=$mcpVisible; Healthy=$mcpHealthy; Unknown=$mcpUnknown; Stale=$mcpStale; SnapshotFresh=$(-not $mcpSnapshotStale); RuntimeFresh=$(-not $runtimeSnapshotStale); ConfigMatch=$(-not $mcpConfigMismatch)")
$lines.Add('')
$lines.Add('## L. Runtime Snapshot')
$lines.Add('')
$lines.Add(($snapshot | ConvertTo-Json -Depth 12))
$lines.Add('')
$lines.Add('## M. Router Reference Integrity')
$lines.Add('')
$lines.Add("Failures=$($referenceFailures.Count); Checked=$($referenceRows.Count)")
foreach ($row in $referenceRows) { $lines.Add("- [$($row.status)] $($row.reference): $($row.reason)") }
$lines.Add('')
$lines.Add('## N. Profile Contamination')
$lines.Add('')
$lines.Add("Count=$($contamination.Count)")
foreach ($row in $contamination) { $lines.Add("- $($row.profile): $($row.name) - $($row.reason)") }
$lines.Add('')
$lines.Add('## O. Static Tests')
$lines.Add('')
if ($tests) { $lines.Add("Passes=$($tests.totals.passes); Failures=$($tests.totals.failures); Skipped=$($tests.totals.skipped); Runtime=$($tests.runtime.powershell)") } else { $lines.Add('UNAVAILABLE: test result JSON not found') }
$lines.Add('')
$lines.Add('## P. Capability Tests')
$lines.Add('')
$lines.Add('- Frontmatter literal/folded parser, trigger provenance, contextual roles, compound tokenizer, runtime filtering, and priority stability are covered by Level 2 tests.')
$lines.Add('')
$lines.Add('## Q. Real Agent Eval')
$lines.Add('')
$lines.Add("Status=$($realAgent.status); Reason=$($realAgent.reason)")
$lines.Add('')
$lines.Add('## R. Routing Decisions')
$lines.Add('')
if ($tests -and $tests.cases) {
    foreach ($case in @($tests.cases)) { $lines.Add("- $($case.intent) / $($case.domains -join ',') / $($case.scale) / Primary=$($case.primary_skill) / Worktree=$($case.worktree.use) / Subagents=$($case.subagents.use)") }
} else { $lines.Add('UNAVAILABLE: no routing case results') }
$lines.Add('')
$lines.Add('## S. 40+ Skill QA')
$lines.Add('')
$lines.Add("SampleCount=$($qaRows.Count)")
foreach ($row in $qaRows) { $lines.Add("- [$($row.status)] $($row.name): $($row.reason)") }
$lines.Add('')
$lines.Add('## T. Windows PowerShell Status')
$lines.Add('')
$lines.Add('- PowerShell 7+: supported execution path.')
$lines.Add('- Windows PowerShell 5.1: clean `PowerShell 7+ required` exit code 64 after UTF-8 BOM handling.')
$lines.Add('')
$lines.Add('## U. Remaining Issues')
$lines.Add('')
foreach ($note in @($full.runtime_truth_notes)) { $lines.Add("- $note") }
$lines.Add("- MCP snapshot freshness: $(if ($mcpSnapshotStale) { 'STALE' } else { 'FRESH' }); Runtime tools freshness: $(if ($runtimeSnapshotStale) { 'STALE' } else { 'FRESH' }); Config parity: $(if ($mcpConfigMismatch) { 'MISMATCH' } else { 'MATCH' }).")
$lines.Add('- Real Agent Eval is not accepted as passed unless an isolated Agent result is present.')
$lines.Add('')
$lines.Add("## READY_FOR_ADAPTIVE_ROUTER: $(if ($ready) { 'YES' } else { 'NO' })")
$lines.Add('')
$lines.Add('Adaptive Router remains out of scope for this reliability release.')
Write-RouteAtomicText -Path $OutputPath -Content ($lines -join "`n")
Write-Output "REPORT GENERATED: $OutputPath"
