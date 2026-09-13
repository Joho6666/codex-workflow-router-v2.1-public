param(
[string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }),
    [string]$RouterPath = '',
    [string]$AgentsPath = '',
    [string]$CatalogPath = '',
    [string]$FullIndexPath = '',
    [string]$SummaryIndexPath = '',
    [string]$CompatIndexPath = '',
    [string]$RuntimeToolsPath = '',
    [string]$McpSnapshotPath = '',
    [string]$ResultPath = ''
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Output 'PowerShell 7+ required. Run this script with pwsh.exe.'
    exit 64
}

if ([string]::IsNullOrWhiteSpace($RouterPath)) { $RouterPath = Join-Path $CodexHome 'WORKFLOW_ROUTER.md' }
if ([string]::IsNullOrWhiteSpace($AgentsPath)) { $AgentsPath = Join-Path $CodexHome 'AGENTS.md' }
if ([string]::IsNullOrWhiteSpace($CatalogPath)) { $CatalogPath = Join-Path $CodexHome 'ROUTING_CATALOG.json' }
if ([string]::IsNullOrWhiteSpace($FullIndexPath)) { $FullIndexPath = Join-Path $CodexHome 'CAPABILITIES_FULL.json' }
if ([string]::IsNullOrWhiteSpace($SummaryIndexPath)) { $SummaryIndexPath = Join-Path $CodexHome 'CAPABILITIES_SUMMARY.json' }
if ([string]::IsNullOrWhiteSpace($CompatIndexPath)) { $CompatIndexPath = Join-Path $CodexHome 'CAPABILITIES.json' }
if ([string]::IsNullOrWhiteSpace($RuntimeToolsPath)) { $RuntimeToolsPath = Join-Path $CodexHome 'RUNTIME_TOOLS.json' }
if ([string]::IsNullOrWhiteSpace($McpSnapshotPath)) { $McpSnapshotPath = Join-Path $CodexHome 'MCP_RUNTIME_STATUS.json' }
if ([string]::IsNullOrWhiteSpace($ResultPath)) { $ResultPath = Join-Path $CodexHome 'WORKFLOW_ROUTER_V2_1_TEST_RESULTS.json' }

$corePath = Join-Path $CodexHome 'scripts\workflow-router-core.ps1'
if (Test-Path -LiteralPath $corePath -PathType Leaf) { . $corePath }

$script:Passes = 0
$script:Failures = 0
$script:Skips = 0
$script:Results = New-Object System.Collections.Generic.List[object]

function Assert-RouteTest {
    param([string]$Name, [bool]$Condition, [string]$Details = '')
    $status = if ($Condition) { 'PASS' } else { 'FAIL' }
    if ($Condition) { $script:Passes++ } else { $script:Failures++ }
    $script:Results.Add([pscustomobject]@{ name=$Name; status=$status; details=$Details; level=$script:CurrentLevel })
    if ($Condition) { Write-Host "[PASS] $Name" -ForegroundColor Green }
    else { Write-Host "[FAIL] $Name :: $Details" -ForegroundColor Red }
}

function Skip-RouteTest {
    param([string]$Name, [string]$Reason)
    $script:Skips++
    $script:Results.Add([pscustomobject]@{ name=$Name; status='SKIPPED'; details=$Reason; level=$script:CurrentLevel })
    Write-Host "[SKIPPED] $Name :: $Reason" -ForegroundColor Yellow
}

function Read-JsonOrNull {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -DateKind String) }
    catch { return $null }
}

function Test-Utf8Bom {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)
}

function Get-CodexSkill {
    param($Entries, [string]$Name)
    $matches = @($Entries | Where-Object { $_.kind -eq 'skill' -and $_.name -eq $Name })
    $codex = @($matches | Where-Object { $_.source_runtime -eq 'codex' })
    if ($codex.Count -gt 0) { return $codex[0] }
    if ($matches.Count -gt 0) { return $matches[0] }
    return $null
}

function ConvertTo-NormalizedGeneratorNode {
    param($Node)
    if ($null -eq $Node) { return $null }
    if ($Node -is [System.Management.Automation.PSCustomObject]) {
        $normalized = [ordered]@{}
        foreach ($property in @($Node.PSObject.Properties | Sort-Object Name)) {
            if ($property.Name -in @('generated_at','observed_at','snapshot_id')) { $normalized[$property.Name] = '<volatile>' }
            else { $normalized[$property.Name] = ConvertTo-NormalizedGeneratorNode $property.Value }
        }
        return [pscustomobject]$normalized
    }
    if (($Node -is [System.Collections.IEnumerable]) -and -not ($Node -is [string])) {
        return @($Node | ForEach-Object { ConvertTo-NormalizedGeneratorNode $_ })
    }
    return $Node
}

function Normalize-GeneratorStructure {
    param($Object)
    if ($null -eq $Object) { return '' }
    return (ConvertTo-NormalizedGeneratorNode $Object | ConvertTo-Json -Depth 50 -Compress)
}

function Invoke-RouteResolver {
    param([string]$Prompt)
    $resolver = Join-Path $CodexHome 'scripts\resolve-workflow-route.ps1'
    if (-not (Test-Path -LiteralPath $resolver -PathType Leaf)) { return $null }
    $raw = & pwsh.exe -NoLogo -NoProfile -File $resolver -CodexHome $CodexHome -Prompt $Prompt
    if ($LASTEXITCODE -ne 0) { return $null }
    return ($raw | ConvertFrom-Json)
}

Write-Host '==================================================' -ForegroundColor Cyan
Write-Host 'LEVEL 1: STATIC CONTRACT' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan
$script:CurrentLevel = 'static'

Assert-RouteTest 'AGENTS.md exists' (Test-Path -LiteralPath $AgentsPath -PathType Leaf)
Assert-RouteTest 'AGENTS references WORKFLOW_ROUTER.md' ((Test-Path -LiteralPath $AgentsPath -PathType Leaf) -and ((Get-Content -Raw -LiteralPath $AgentsPath) -match 'WORKFLOW_ROUTER\.md'))
Assert-RouteTest 'AGENTS references ROUTING_CATALOG.json' ((Test-Path -LiteralPath $AgentsPath -PathType Leaf) -and ((Get-Content -Raw -LiteralPath $AgentsPath) -match 'ROUTING_CATALOG\.json'))
Assert-RouteTest 'Router references ROUTING_CATALOG.json' ((Test-Path -LiteralPath $RouterPath -PathType Leaf) -and ((Get-Content -Raw -LiteralPath $RouterPath) -match 'ROUTING_CATALOG\.json'))

$catalog = Read-JsonOrNull $CatalogPath
$full = Read-JsonOrNull $FullIndexPath
$summary = Read-JsonOrNull $SummaryIndexPath
$compat = Read-JsonOrNull $CompatIndexPath
$runtimeTools = Read-JsonOrNull $RuntimeToolsPath
$mcpSnapshot = Read-JsonOrNull $McpSnapshotPath

Assert-RouteTest 'ROUTING_CATALOG.json exists and parses' ($null -ne $catalog)
Assert-RouteTest 'CAPABILITIES_FULL.json parses' ($null -ne $full)
Assert-RouteTest 'CAPABILITIES_SUMMARY.json parses' ($null -ne $summary)
Assert-RouteTest 'CAPABILITIES.json parses' ($null -ne $compat)
Assert-RouteTest 'MCP_RUNTIME_STATUS.json exists and parses' ($null -ne $mcpSnapshot)
Assert-RouteTest 'RUNTIME_TOOLS.json parses' ($null -ne $runtimeTools)

if ($null -ne $catalog) {
    foreach ($key in @('intents','domains','risk_rules','scale_rules','profiles','skill_role_bindings','provider_mappings','verification_mappings','candidate_scoring','runtime_policy','worktree_rules','subagent_rules','execution_gate_rules','profile_contamination','qa_rules')) {
        Assert-RouteTest "Catalog contains $key" ($null -ne $catalog.PSObject.Properties[$key])
    }
    Assert-RouteTest 'Catalog schema_version is 2.1' ([string]$catalog.schema_version -eq '2.1')
}
if ($null -ne $full) {
    Assert-RouteTest 'Full index schema_version is 2.1' ([string]$full.schema_version -eq '2.1')
    Assert-RouteTest 'Full index has entries' (@($full.entries).Count -gt 0)
    Assert-RouteTest 'Full index parser failure count is zero' ($full.statistics.description_parser_failure_count -eq 0)
    Assert-RouteTest 'Full index has classification_audit' ($null -ne $full.classification_audit)
    Assert-RouteTest 'Full index has profile_contamination audit' ($null -ne $full.classification_audit.profile_contamination)
}
if ($null -ne $summary) {
    Assert-RouteTest 'Summary index schema_version is 2.1' ([string]$summary.schema_version -eq '2.1')
    Assert-RouteTest 'Summary has 13 profiles' (@($summary.profiles.PSObject.Properties).Count -eq 13)
    Assert-RouteTest 'Summary profiles use primary_skill_candidates' ($null -ne $summary.profiles.frontend.primary_skill_candidates)
    Assert-RouteTest 'Summary profiles use provider_candidates' ($null -ne $summary.profiles.frontend.provider_candidates)
    Assert-RouteTest 'Summary exposes strict Skill runtime filter' ($null -ne $summary.skill_runtime_filter -and @($summary.skill_runtime_filter.records).Count -gt 0)
    $summaryBuildKeilRuntime = @($summary.skill_runtime_filter.records | Where-Object name -eq 'build-keil') | Select-Object -First 1
    Assert-RouteTest 'Summary marks Mirasim-only Skill as ineligible' ($null -ne $summaryBuildKeilRuntime -and $summaryBuildKeilRuntime.eligible_for_codex_route -ne $true)
}
if ($null -ne $compat) {
    Assert-RouteTest 'Compatibility pointer schema_version is 2.1' ([string]$compat.schema_version -eq '2.1')
    Assert-RouteTest 'Compatibility pointer points to Summary and Full' (($null -ne $compat.summary_path) -and ($null -ne $compat.full_path))
}
if ($null -ne $mcpSnapshot) {
    Assert-RouteTest 'MCP snapshot has observed_at' (-not [string]::IsNullOrWhiteSpace([string]$mcpSnapshot.observed_at))
    Assert-RouteTest 'MCP snapshot has snapshot_id' (-not [string]::IsNullOrWhiteSpace([string]$mcpSnapshot.snapshot_id))
    Assert-RouteTest 'MCP snapshot has stale policy' ([bool](($mcpSnapshot.PSObject.Properties.Name -contains 'stale_after_seconds') -and ($mcpSnapshot.PSObject.Properties.Name -contains 'stale')))
    Assert-RouteTest 'MCP snapshot has server records' (@($mcpSnapshot.servers).Count -gt 0)
    $configuredMcp = @(Get-ConfiguredMcpNames -ConfigPath (Join-Path $CodexHome 'config.toml'))
    $snapshotMcp = @($mcpSnapshot.servers | ForEach-Object { [string]$_.server })
    Assert-RouteTest 'MCP snapshot matches current config' ((@(Get-RouteStableUnique -Items $configuredMcp | Sort-Object) -join '|') -eq (@(Get-RouteStableUnique -Items $snapshotMcp | Sort-Object) -join '|'))
    Assert-RouteTest 'MCP snapshot is fresh by clock' (-not (Test-RouteSnapshotStale -Snapshot $mcpSnapshot -ObservedAt ([string]$mcpSnapshot.observed_at) -DefaultSeconds ([int]$mcpSnapshot.stale_after_seconds)))
}
if ($null -ne $runtimeTools) {
    Assert-RouteTest 'Runtime tools schema_version is 2.1' ([string]$runtimeTools.schema_version -eq '2.1')
    Assert-RouteTest 'Runtime tools snapshot has observed_at' (-not [string]::IsNullOrWhiteSpace([string]$runtimeTools.observed_at))
    Assert-RouteTest 'Runtime tools snapshot has snapshot_id' (-not [string]::IsNullOrWhiteSpace([string]$runtimeTools.snapshot_id))
    Assert-RouteTest 'Runtime tools snapshot has stale field' ([bool]($runtimeTools.PSObject.Properties.Name -contains 'stale'))
    Assert-RouteTest 'Runtime tools snapshot is fresh by clock' (-not (Test-RouteSnapshotStale -Snapshot $runtimeTools -ObservedAt ([string]$runtimeTools.observed_at) -DefaultSeconds ([int]$runtimeTools.stale_after_seconds)))
}

$scriptPaths = @(
    (Join-Path $CodexHome 'scripts\workflow-router-core.ps1'),
    (Join-Path $CodexHome 'scripts\resolve-workflow-route.ps1'),
    (Join-Path $CodexHome 'scripts\update-capability-index.ps1'),
    (Join-Path $CodexHome 'scripts\update-mcp-runtime-status.ps1'),
    (Join-Path $CodexHome 'scripts\generate-workflow-router-report.ps1'),
    (Join-Path $CodexHome 'scripts\test-workflow-router.ps1')
)
foreach ($path in $scriptPaths) {
    Assert-RouteTest "Script exists: $([System.IO.Path]::GetFileName($path))" (Test-Path -LiteralPath $path -PathType Leaf)
    Assert-RouteTest "Script has UTF-8 BOM: $([System.IO.Path]::GetFileName($path))" (Test-Utf8Bom $path)
}

$testText = Get-Content -Raw -LiteralPath $PSCommandPath
$legacyEvaluatorMarker = ('Evaluate' + '-RouterContract')
Assert-RouteTest 'Self-Test does not define legacy route evaluator' (-not ($testText -match [regex]::Escape($legacyEvaluatorMarker)))
Assert-RouteTest 'Self-Test does not branch on prompt to implement routing' (-not ($testText -match '(?im)^\s*if\s*\(\s*\$[^\r\n]*(prompt|taskprompt|task)[^\r\n]*-match'))
$generatorPath = Join-Path $CodexHome 'scripts\update-capability-index.ps1'
if (Test-Path -LiteralPath $generatorPath -PathType Leaf) {
    $generatorText = Get-Content -Raw -LiteralPath $generatorPath
    Assert-RouteTest 'Generator does not hardcode MCP health truth' (-not ($generatorText -match "node_repl|yuanlitu_easyeda|cloudbase"))
    Assert-RouteTest 'Generator references Catalog' ($generatorText -match 'ROUTING_CATALOG|CatalogPath')
}
if (Test-Path -LiteralPath $corePath -PathType Leaf) {
    . $corePath
    $coreText = Get-Content -Raw -LiteralPath $corePath
    $candidateBody = [regex]::Match($coreText, 'function Get-CandidateRankings \{(?s).*?(?=function Get-ProfileCandidateSet)').Value
    Assert-RouteTest 'Legacy task_types do not affect route scoring' (-not ($candidateBody -match 'task_types'))
    Assert-RouteTest 'Core has no order-breaking Sort-Object -Unique' (-not ($coreText -match '(?im)Sort-Object[^\r\n]*-Unique'))
    $compoundTokens = @(Get-RouteTokens 'requesting-code-review')
    foreach ($token in @('requesting-code-review','requesting','code','review')) {
        Assert-RouteTest "Tokenizer keeps token $token" ($compoundTokens -contains $token)
    }
    $priorityFixture = @(
        [pscustomobject]@{ name='priority-low'; score=50; priority=50; confidence=0.95; source_runtime='codex' },
        [pscustomobject]@{ name='priority-high'; score=50; priority=95; confidence=0.95; source_runtime='codex' }
    )
    $priorityOrder = @(Sort-RouteCandidates -Candidates $priorityFixture)
    $priorityOrderAgain = @(Sort-RouteCandidates -Candidates $priorityFixture)
    Assert-RouteTest 'Priority 95 precedes priority 50 at equal score' ($priorityOrder[0].priority -eq 95)
    Assert-RouteTest 'Candidate sort is stable across repeated runs' ((@($priorityOrder.name) -join '|') -eq (@($priorityOrderAgain.name) -join '|'))
    $stableValues = @(Get-RouteStableUnique -Items @('second','first','second','third','first'))
    Assert-RouteTest 'Stable unique preserves first occurrence order' ((@($stableValues) -join '|') -eq 'second|first|third')
    $stableObjects = @(Get-RouteStableUnique -Items @([pscustomobject]@{name='b'},[pscustomobject]@{name='a'},[pscustomobject]@{name='b'}) -Property 'name')
    Assert-RouteTest 'Stable object unique preserves first occurrence order' ((@($stableObjects | ForEach-Object name) -join '|') -eq 'b|a')
    $staleFixture = [pscustomobject]@{ kind='skill'; source_runtime='codex'; name='stale-skill'; capabilities=@(); availability=[pscustomobject]@{ discoverable_by_codex=$true; stale=$true; runtime_available=$true } }
    Assert-RouteTest 'Stale runtime skill is not eligible' (-not (Test-CodexSkillRuntime $staleFixture))
    if ($null -ne $catalog -and $null -ne $full -and $null -ne $summary) {
        $references = @(Test-WorkflowRouterReferenceIntegrity -Catalog $catalog -FullIndex $full -Summary $summary -RouterPath $RouterPath)
        Assert-RouteTest 'Router Reference Integrity has checks' ($references.Count -gt 0)
        Assert-RouteTest 'Router Reference Integrity has no hard failures' (@($references | Where-Object status -eq 'FAIL').Count -eq 0)
    }
}

Write-Host '==================================================' -ForegroundColor Cyan
Write-Host 'LEVEL 2: CAPABILITY / PARSER / RUNTIME' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan
$script:CurrentLevel = 'capability'

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('workflow-router-fixtures-' + [guid]::NewGuid().ToString('N'))
$fixtureOut = Join-Path $fixtureRoot 'out'
if (Test-Path -LiteralPath $generatorPath -PathType Leaf) {
    New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'skills\fixture-literal'), (Join-Path $fixtureRoot 'skills\fixture-folded'), (Join-Path $fixtureRoot 'skills\fixture-single'), (Join-Path $fixtureRoot 'skills\fixture-empty'), (Join-Path $fixtureRoot 'skills\fixture-trigger') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'mirasim\skills') -Force | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding($true)
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'skills\fixture-literal\SKILL.md'), "---`nname: fixture-literal`ndescription: |`n  literal line one`n  literal line two`n---`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'skills\fixture-folded\SKILL.md'), "---`nname: fixture-folded`ndescription: >-`n  folded line one`n  folded line two`n---`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'skills\fixture-single\SKILL.md'), "---`nname: fixture-single`ndescription: single line description`n---`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'skills\fixture-empty\SKILL.md'), "---`nname: fixture-empty`ndescription:`n---`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'skills\fixture-trigger\SKILL.md'), "---`nname: fixture-trigger`ndescription: Use when a fixture trigger is needed.`ntriggers:`n  - explicit fixture trigger`n---`n", $utf8)
    New-Item -ItemType Directory -Path $fixtureOut -Force | Out-Null
    & pwsh.exe -NoLogo -NoProfile -File $generatorPath -CodexHome $fixtureRoot -MirasimHome (Join-Path $fixtureRoot 'mirasim') -CatalogPath $CatalogPath -RuntimeToolInventoryPath (Join-Path $fixtureRoot 'missing-tools.json') -RuntimeSnapshotPath (Join-Path $fixtureRoot 'missing-snapshot.json') -FullOutputPath (Join-Path $fixtureOut 'full.json') -SummaryOutputPath (Join-Path $fixtureOut 'summary.json') -CompatibilityOutputPath (Join-Path $fixtureOut 'compat.json') | Out-Host
    $fixtureCode = $LASTEXITCODE
    $fixtureFull = Read-JsonOrNull (Join-Path $fixtureOut 'full.json')
    Assert-RouteTest 'Fixture Generator exits successfully' ($fixtureCode -eq 0)
    Assert-RouteTest 'Fixture parser failure count is zero' ($null -ne $fixtureFull -and $fixtureFull.statistics.description_parser_failure_count -eq 0)
    $fixtureEntries = @($fixtureFull.entries | Where-Object { $_.kind -eq 'skill' })
    $literal = $fixtureEntries | Where-Object name -eq 'fixture-literal'
    $folded = $fixtureEntries | Where-Object name -eq 'fixture-folded'
    $empty = $fixtureEntries | Where-Object name -eq 'fixture-empty'
    $explicit = $fixtureEntries | Where-Object name -eq 'fixture-trigger'
    Assert-RouteTest 'Literal block scalar preserves newline' ($null -ne $literal -and $literal.description -match 'literal line one\r?\nliteral line two')
    Assert-RouteTest 'Folded block scalar joins lines' ($null -ne $folded -and $folded.description -eq 'folded line one folded line two')
    Assert-RouteTest 'Empty description counted separately' ($null -ne $fixtureFull -and $fixtureFull.statistics.description_empty_count -eq 1)
    Assert-RouteTest 'Explicit trigger provenance is frontmatter' ($null -ne $explicit -and $explicit.trigger_source -eq 'frontmatter')
    Assert-RouteTest 'Trigger statistics distinguish explicit and fallback' ($null -ne $fixtureFull.statistics.explicit_trigger_count -and $null -ne $fixtureFull.statistics.fallback_description_count)
    $fixtureFullStructure = Normalize-GeneratorStructure $fixtureFull
    $fixtureSummary = Read-JsonOrNull (Join-Path $fixtureOut 'summary.json')
    $fixtureSummaryStructure = Normalize-GeneratorStructure $fixtureSummary
    & pwsh.exe -NoLogo -NoProfile -File $generatorPath -CodexHome $fixtureRoot -MirasimHome (Join-Path $fixtureRoot 'mirasim') -CatalogPath $CatalogPath -RuntimeToolInventoryPath (Join-Path $fixtureRoot 'missing-tools.json') -RuntimeSnapshotPath (Join-Path $fixtureRoot 'missing-snapshot.json') -FullOutputPath (Join-Path $fixtureOut 'full.json') -SummaryOutputPath (Join-Path $fixtureOut 'summary.json') -CompatibilityOutputPath (Join-Path $fixtureOut 'compat.json') | Out-Host
    $fixtureSecondCode = $LASTEXITCODE
    $fixtureFullSecond = Read-JsonOrNull (Join-Path $fixtureOut 'full.json')
    $fixtureSummarySecond = Read-JsonOrNull (Join-Path $fixtureOut 'summary.json')
    Assert-RouteTest 'Fixture Generator is stable on consecutive runs' ($fixtureSecondCode -eq 0 -and (Normalize-GeneratorStructure $fixtureFullSecond) -eq $fixtureFullStructure -and (Normalize-GeneratorStructure $fixtureSummarySecond) -eq $fixtureSummaryStructure)
} else {
    Skip-RouteTest 'Fixture parser tests' 'Generator is not present yet'
}

if ($null -ne $full) {
    $systematic = Get-CodexSkill $full.entries 'systematic-debugging'
    $verification = Get-CodexSkill $full.entries 'verification-before-completion'
    $kicad = Get-CodexSkill $full.entries 'kicad'
    $buildKeil = @($full.entries | Where-Object { $_.kind -eq 'skill' -and $_.name -eq 'build-keil' }) | Select-Object -First 1
    Assert-RouteTest 'systematic-debugging is debugging primary' ($null -ne $systematic -and $systematic.routing_roles.debugging -contains 'primary')
    Assert-RouteTest 'verification-before-completion is verification only' ($null -ne $verification -and $verification.roles -contains 'verification' -and -not ($verification.roles -contains 'primary'))
    Assert-RouteTest 'kicad has contextual EDA primary role' ($null -ne $kicad -and $kicad.routing_roles.eda -contains 'primary')
    Assert-RouteTest 'kicad is supporting in embedded context' ($null -ne $kicad -and $kicad.routing_roles.embedded -contains 'supporting')
    Assert-RouteTest 'Mirasim-only build-keil is not Codex-discoverable' ($null -ne $buildKeil -and $buildKeil.availability.discoverable_by_codex -ne $true)
}

Write-Host '==================================================' -ForegroundColor Cyan
Write-Host 'LEVEL 3: PROFILE CONTAMINATION / ROUTING CONTRACT' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan
$script:CurrentLevel = 'profile'

if ($null -ne $summary) {
    Assert-RouteTest 'Backend profile excludes kicad' (-not (@($summary.profiles.backend.primary_skill_candidates, $summary.profiles.backend.supporting_skill_candidates, $summary.profiles.backend.verification_candidates) -contains 'kicad'))
    Assert-RouteTest 'Backend profile excludes BOM' (-not (@($summary.profiles.backend.primary_skill_candidates, $summary.profiles.backend.supporting_skill_candidates, $summary.profiles.backend.verification_candidates) -contains 'bom'))
    Assert-RouteTest 'Backend profile excludes citation-verify' (-not (@($summary.profiles.backend.primary_skill_candidates, $summary.profiles.backend.supporting_skill_candidates, $summary.profiles.backend.verification_candidates) -contains 'citation-verify'))
    Assert-RouteTest 'Frontend profile excludes video-shotcraft as primary' (-not (@($summary.profiles.frontend.primary_skill_candidates) -contains 'video-shotcraft'))
    Assert-RouteTest 'Academic profile excludes firmware and PCB skills' (-not (@($summary.profiles.academic.primary_skill_candidates, $summary.profiles.academic.supporting_skill_candidates) | Where-Object { $_ -match 'firmware|kicad|pcb' }))
    Assert-RouteTest 'Embedded profile excludes PCB tools for firmware-only default' (-not (@($summary.profiles.embedded.primary_skill_candidates) -contains 'kicad'))
    Assert-RouteTest 'Mirasim-only build-keil is absent from Codex candidates' (-not (@($summary.profiles.embedded.primary_skill_candidates, $summary.profiles.embedded.supporting_skill_candidates, $summary.profiles.embedded.verification_candidates) -contains 'build-keil'))
    Assert-RouteTest 'Backend profile excludes embedded firmware' (-not (@($summary.profiles.backend.primary_skill_candidates, $summary.profiles.backend.supporting_skill_candidates, $summary.profiles.backend.verification_candidates) -contains 'embedded-firmware-keil'))
    Assert-RouteTest 'EDA candidates exclude embedded firmware' (-not (@($summary.profiles.eda.primary_skill_candidates, $summary.profiles.eda.supporting_skill_candidates, $summary.profiles.eda.verification_candidates) -contains 'embedded-firmware-keil'))
}

$cases = @(
    [pscustomobject]@{ id='CASE_1_README'; prompt='README 改一个错别字'; intent='maintenance'; scale='FAST'; primary=$null; worktree=$false; subagents=$false },
    [pscustomobject]@{ id='CASE_2_REACT_BUG'; prompt='修复 React 登录页偶现白屏'; intent='bugfix'; domain='frontend'; scale='STANDARD'; primary='systematic-debugging'; worktree=$false },
    [pscustomobject]@{ id='CASE_3_FRONTEND_REFACTOR'; prompt='重构整个前端 Design System'; intent='refactor'; domain='frontend'; scale='DEEP'; primary='frontend-design' },
    [pscustomobject]@{ id='CASE_4_STM32_FIRMWARE'; prompt='实现 STM32 温湿度采集固件'; intent='development'; domain='embedded'; scale='DEEP'; primary='embedded-firmware-keil'; worktree=$false; subagents=$false },
    [pscustomobject]@{ id='CASE_5_STM32_PCB'; prompt='设计 STM32 温湿度采集板的原理图和 PCB'; domain='eda'; primary='kicad' },
    [pscustomobject]@{ id='CASE_6_ACADEMIC_WORD'; prompt='修改一篇本科毕业论文并输出 Word'; intent='revision'; domain='academic'; scale='STANDARD'; primary='chinese-academic-writing-cn'; worktree=$false; subagents=$false },
    [pscustomobject]@{ id='CASE_7_PARALLEL_MODULES'; prompt='同时实现地图模块、登录模块、数据库模块，三个模块尽量独立开发'; scale='DEEP'; worktree=$true; subagents=$true },
    [pscustomobject]@{ id='CASE_8_VERCEL'; prompt='部署 Next.js 项目到 Vercel'; domain='deployment'; provider='vercel'; primary=$null }
)
$caseResults = New-Object System.Collections.Generic.List[object]
foreach ($case in $cases) {
    $route = Invoke-RouteResolver $case.prompt
    if ($null -eq $route) {
        Assert-RouteTest "$($case.id) resolver returns JSON" $false 'Resolver missing or returned non-zero'
        continue
    }
    $caseResults.Add($route)
    Assert-RouteTest "$($case.id) has intent/domains" ((-not [string]::IsNullOrWhiteSpace([string]$route.intent)) -and ($null -ne $route.domains))
    if ($case.PSObject.Properties['intent']) { Assert-RouteTest "$($case.id) intent=$($case.intent)" ($route.intent -eq $case.intent) }
    if ($case.PSObject.Properties['domain']) { Assert-RouteTest "$($case.id) contains domain=$($case.domain)" (@($route.domains) -contains $case.domain) }
    if ($case.PSObject.Properties['scale']) { Assert-RouteTest "$($case.id) scale=$($case.scale)" ($route.scale -eq $case.scale) }
    if ($case.PSObject.Properties['primary']) { Assert-RouteTest "$($case.id) primary constraint" ($route.primary_skill -eq $case.primary) }
    if ($case.PSObject.Properties['worktree']) { Assert-RouteTest "$($case.id) worktree constraint" ($route.worktree.use -eq $case.worktree) }
    if ($case.PSObject.Properties['subagents']) { Assert-RouteTest "$($case.id) subagent constraint" ($route.subagents.use -eq $case.subagents) }
    if ($case.PSObject.Properties['provider']) { Assert-RouteTest "$($case.id) provider constraint" (@($route.providers) -contains $case.provider) }
    Assert-RouteTest "$($case.id) has worktree reason" (-not [string]::IsNullOrWhiteSpace([string]$route.worktree.reason))
    Assert-RouteTest "$($case.id) has subagent reason" (-not [string]::IsNullOrWhiteSpace([string]$route.subagents.reason))
    Assert-RouteTest "$($case.id) minimal primary count" (@($route.primary_skill).Count -le 1)
    Assert-RouteTest "$($case.id) minimal supporting count" (@($route.supporting_skills).Count -le 4)
}

$singleModuleRoute = Invoke-RouteResolver '并行实现一个模块'
if ($null -ne $singleModuleRoute) {
    Assert-RouteTest 'Single-module parallel task does not use Worktree' (-not $singleModuleRoute.worktree.use)
    Assert-RouteTest 'Single-module parallel task does not use Subagents' (-not $singleModuleRoute.subagents.use)
}
$firmwareRoute = Invoke-RouteResolver '实现 STM32 温湿度采集固件'
if ($null -ne $firmwareRoute) {
    foreach ($externalSkill in @('build-keil','flash-keil','serial-monitor')) {
        Assert-RouteTest "Strict Codex route excludes Mirasim-only $externalSkill" (-not (@($firmwareRoute.supporting_skills,$firmwareRoute.verification) -contains $externalSkill))
    }
}

Write-Host '==================================================' -ForegroundColor Cyan
Write-Host 'LEVEL 4: REAL AGENT ROUTING EVAL' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan
$script:CurrentLevel = 'real-agent'
$realEvalPath = Join-Path $CodexHome 'REAL_AGENT_EVAL.json'
$realEval = Read-JsonOrNull $realEvalPath
if ($null -eq $realEval) {
    $realEvalStatus = 'NOT_RUN'
    $realEvalReason = 'No top-level isolated Agent Eval result was supplied to the PowerShell runner.'
    Skip-RouteTest 'Real Agent Eval' $realEvalReason
} else {
    $realEvalStatus = [string]$realEval.status
    $realEvalReason = [string]$realEval.reason
    Assert-RouteTest 'Real Agent Eval status is explicit' ($realEvalStatus -in @('PASS','FAIL','NOT_RUN'))
    if ($realEvalStatus -eq 'NOT_RUN') { Skip-RouteTest 'Real Agent Eval execution' $realEvalReason }
    if ($realEvalStatus -eq 'PASS') {
        $realCases = @($realEval.cases)
        Assert-RouteTest 'Real Agent Eval has exactly 8 cases' ($realCases.Count -eq 8)
        $strictRecords = if ($null -ne $summary -and $null -ne $summary.skill_runtime_filter) { @($summary.skill_runtime_filter.records) } else { @() }
        $realSkillFailures = New-Object System.Collections.Generic.List[string]
        foreach ($realCase in $realCases) {
            foreach ($skillName in @($realCase.primary_skill) + @($realCase.supporting_skills)) {
                if ([string]::IsNullOrWhiteSpace([string]$skillName)) { continue }
                $eligible = @($strictRecords | Where-Object { $_.name -eq $skillName -and $_.eligible_for_codex_route -eq $true })
                if ($eligible.Count -eq 0) { $realSkillFailures.Add("$($realCase.id):$skillName") }
            }
            foreach ($providerName in @($realCase.providers)) {
                if ($null -eq $catalog -or $null -eq $catalog.provider_mappings.PSObject.Properties[$providerName]) { $realSkillFailures.Add("$($realCase.id):provider:$providerName") }
            }
            foreach ($externalSkill in @('build-keil','flash-keil','serial-monitor')) {
                if (@($realCase.supporting_skills,$realCase.verification) -contains $externalSkill) { $realSkillFailures.Add("$($realCase.id):external:$externalSkill") }
            }
        }
        Assert-RouteTest 'Real Agent Eval selected skills pass strict runtime filter' ($realSkillFailures.Count -eq 0) ($realSkillFailures -join ', ')
    }
}

$resultPasses = @($script:Results | Where-Object status -eq 'PASS').Count
$resultFailures = @($script:Results | Where-Object status -eq 'FAIL').Count
$resultSkipped = @($script:Results | Where-Object status -eq 'SKIPPED').Count
$resultObject = [ordered]@{
    schema_version = '2.1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    runtime = [ordered]@{ powershell = $PSVersionTable.PSVersion.ToString(); test_script = $PSCommandPath }
    totals = [ordered]@{ passes=$resultPasses; failures=$resultFailures; skipped=$resultSkipped }
    real_agent_eval = [ordered]@{ status=$realEvalStatus; reason=$realEvalReason; path=$realEvalPath }
    cases = $caseResults.ToArray()
    results = $script:Results.ToArray()
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ResultPath) | Out-Null
$resultObject | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ResultPath -Encoding UTF8

Write-Host '==================================================' -ForegroundColor Cyan
Write-Host "SELF-TEST COMPLETE: Passes=$resultPasses, Failures=$resultFailures, Skipped=$resultSkipped" -ForegroundColor $(if ($resultFailures -eq 0) { 'Green' } else { 'Red' })
Write-Host "RESULT_FILE=$ResultPath" -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan

if (Test-Path -LiteralPath $fixtureRoot -PathType Container) {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}
if ($resultFailures -gt 0) { exit 1 }
exit 0
