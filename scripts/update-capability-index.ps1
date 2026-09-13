param(
[string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }),
[string]$MirasimHome = $(if ($env:MIRASIM_HOME) { $env:MIRASIM_HOME } else { Join-Path $env:USERPROFILE '.mirasim' }),
    [string]$CatalogPath = '',
    [string]$FullOutputPath = '',
    [string]$SummaryOutputPath = '',
    [string]$CompatibilityOutputPath = '',
    [string]$RuntimeToolInventoryPath = '',
    [string]$RuntimeSnapshotPath = '',
    [int]$LockTimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Output 'PowerShell 7+ required. Run this script with pwsh.exe.'
    exit 64
}

if ([string]::IsNullOrWhiteSpace($CatalogPath)) { $CatalogPath = Join-Path $CodexHome 'ROUTING_CATALOG.json' }
if ([string]::IsNullOrWhiteSpace($FullOutputPath)) { $FullOutputPath = Join-Path $CodexHome 'CAPABILITIES_FULL.json' }
if ([string]::IsNullOrWhiteSpace($SummaryOutputPath)) { $SummaryOutputPath = Join-Path $CodexHome 'CAPABILITIES_SUMMARY.json' }
if ([string]::IsNullOrWhiteSpace($CompatibilityOutputPath)) { $CompatibilityOutputPath = Join-Path $CodexHome 'CAPABILITIES.json' }
if ([string]::IsNullOrWhiteSpace($RuntimeToolInventoryPath)) { $RuntimeToolInventoryPath = Join-Path $CodexHome 'RUNTIME_TOOLS.json' }
if ([string]::IsNullOrWhiteSpace($RuntimeSnapshotPath)) { $RuntimeSnapshotPath = Join-Path $CodexHome 'MCP_RUNTIME_STATUS.json' }

. (Join-Path $PSScriptRoot 'workflow-router-core.ps1')
$catalog = Get-WorkflowRouterCatalog -CatalogPath $CatalogPath
$runtimeTools = $null
$runtimeSnapshot = $null
if (Test-Path -LiteralPath $RuntimeToolInventoryPath -PathType Leaf) { $runtimeTools = Read-WorkflowRouterJson -Path $RuntimeToolInventoryPath }
if (Test-Path -LiteralPath $RuntimeSnapshotPath -PathType Leaf) { $runtimeSnapshot = Read-WorkflowRouterJson -Path $RuntimeSnapshotPath }

function Get-ConfigMcpNames {
    param([string]$Path)
    $names = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    foreach ($line in Get-Content -LiteralPath $Path) {
        $match = [regex]::Match($line, '^\[mcp_servers\.([^\.\]]+)(?:\.[^\.\]]+)?\]$')
        if ($match.Success -and -not ($names -contains $match.Groups[1].Value)) { $names.Add($match.Groups[1].Value) }
    }
    return @($names)
}

function Get-EntryRolesForIndex {
    param($Catalog, [string]$Name, $Metadata)
    return Get-RouteRoleBindings -Catalog $Catalog -Name $Name -Metadata $Metadata
}

function Get-PluginManifests {
    param([string]$Root)
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Root -Recurse -Filter 'plugin.json' -File -ErrorAction SilentlyContinue | Where-Object { $_.Directory.Name -eq '.codex-plugin' } | Sort-Object FullName)
}

function Get-HookLeafRecords {
    param($Node, [string]$Path = 'hooks')
    $records = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Node) { return @() }
    if (($Node -is [System.Collections.IEnumerable]) -and -not ($Node -is [string]) -and -not ($Node -is [System.Collections.IDictionary])) {
        $index = 0
        foreach ($item in $Node) {
            foreach ($record in @(Get-HookLeafRecords -Node $item -Path "$Path[$index]")) { $records.Add($record) }
            $index++
        }
        return $records.ToArray()
    }
    if ($Node -is [System.Management.Automation.PSCustomObject]) {
        $props = @($Node.PSObject.Properties)
        $hasAction = @($props | Where-Object { $_.Name -in @('command','type','action','script') }).Count -gt 0
        if ($hasAction) { $records.Add([pscustomobject]@{ path=$Path; node=$Node }) }
        foreach ($property in $props) {
            if ($property.Name -in @('command','type','action','script')) { continue }
            foreach ($record in @(Get-HookLeafRecords -Node $property.Value -Path "$Path.$($property.Name)")) { $records.Add($record) }
        }
    }
    return $records.ToArray()
}

function New-IndexEntry {
    param(
        [string]$Name,
        [string]$Kind,
        [string]$Source,
        [string]$SourceRuntime,
        [string]$Path,
        $Version,
        [string]$Description,
        [string[]]$Triggers,
        [string]$TriggerSource,
        [string[]]$TriggerEvidence,
        $Classification,
        [hashtable]$RoutingRoles,
        [int]$Priority,
        [hashtable]$Availability,
        [string[]]$TaskTypes
    )
    $classificationItems = @($Classification.Items)
    $capabilities = @(Get-RouteStableUnique -Items @($classificationItems | ForEach-Object { [string]$_.capability }))
    $roles = @(Get-RouteUnionRoles -RoutingRoles $RoutingRoles)
    $routingRoleObject = [ordered]@{}
    foreach ($roleKey in $RoutingRoles.Keys) { $routingRoleObject[$roleKey] = @($RoutingRoles[$roleKey]) }
    $confidence = if ($classificationItems.Count -gt 0) { [double](@($classificationItems | Measure-Object -Property confidence -Maximum).Maximum) } else { 0.0 }
    return [pscustomobject][ordered]@{
        name=$Name
        kind=$Kind
        source=$Source
        source_runtime=$SourceRuntime
        path=$Path
        version=$Version
        description=if ($null -eq $Description) { '' } else { $Description }
        triggers=@($Triggers)
        trigger_source=$TriggerSource
        trigger_evidence=@($TriggerEvidence)
        capabilities=@($capabilities)
        classification=@($classificationItems)
        task_types=if ($null -eq $TaskTypes) { @() } else { @($TaskTypes) }
        roles=@($roles)
        routing_roles=$routingRoleObject
        role_evidence=if ($RoutingRoles.Count -gt 0) { @('ROUTING_CATALOG.skill_role_bindings') } else { @() }
        priority=$Priority
        confidence=$confidence
        evidence=@($classificationItems | ForEach-Object { $_.evidence })
        classification_audit=$Classification.Audit
        availability=$Availability
    }
}

$entries = New-Object System.Collections.Generic.List[object]
$parserStats = [ordered]@{
    skill_count=0
    description_normal_count=0
    description_empty_count=0
    description_parser_failure_count=0
    trigger_extracted_count=0
    trigger_empty_count=0
    explicit_trigger_count=0
    derived_trigger_count=0
    fallback_description_count=0
    empty_trigger_count=0
}

$roots = @(
    [pscustomobject]@{ path=(Join-Path $CodexHome 'skills'); runtime='codex' },
    [pscustomobject]@{ path=(Join-Path $MirasimHome 'skills'); runtime='mirasim' }
)
foreach ($rootInfo in $roots) {
    if (-not (Test-Path -LiteralPath $rootInfo.path -PathType Container)) { continue }
    foreach ($file in @(Get-ChildItem -LiteralPath $rootInfo.path -Recurse -Filter 'SKILL.md' -File -ErrorAction SilentlyContinue | Sort-Object FullName)) {
        $parser = Get-RouteFrontMatter -Path $file.FullName
        $parserStats.skill_count++
        if ($parser.DescriptionParserFailure) { $parserStats.description_parser_failure_count++ }
        $description = if ($parser.Metadata.Contains('description')) { [string]$parser.Metadata['description'] } else { '' }
        if ([string]::IsNullOrWhiteSpace($description)) { $parserStats.description_empty_count++ } else { $parserStats.description_normal_count++ }
        $trigger = Get-RouteTriggerInfo -Parser $parser
        if ($trigger.values.Count -gt 0 -and $trigger.source -ne 'fallback_description') { $parserStats.trigger_extracted_count++ }
        if ($trigger.source -eq 'none') { $parserStats.trigger_empty_count++; $parserStats.empty_trigger_count++ }
        elseif ($trigger.source -eq 'frontmatter') { $parserStats.explicit_trigger_count++ }
        elseif ($trigger.source -eq 'fallback_description') { $parserStats.fallback_description_count++ }
        else { $parserStats.derived_trigger_count++ }
        $classification = Get-RouteClassification -Catalog $catalog -Name $file.Directory.Name -Description $description -Triggers @($trigger.values) -Metadata $parser.Metadata -ParserFailure $parser.DescriptionParserFailure
        $roles = Get-EntryRolesForIndex -Catalog $catalog -Name $file.Directory.Name -Metadata $parser.Metadata
        $priorityProperty = $catalog.priority_overrides.PSObject.Properties[$file.Directory.Name]
        $priority = if ($null -ne $priorityProperty) { [int]$priorityProperty.Value } else { 50 }
        $availability = New-RouteAvailability -Overrides @{
            installed=$true
            discoverable_by_codex=if ($rootInfo.runtime -eq 'codex') { $true } else { $null }
            stale=$null
        }
        $entry = New-IndexEntry -Name $file.Directory.Name -Kind 'skill' -Source $rootInfo.path -SourceRuntime $rootInfo.runtime -Path $file.FullName -Version $null -Description $description -Triggers @($trigger.values) -TriggerSource $trigger.source -TriggerEvidence @($trigger.evidence) -Classification $classification -RoutingRoles $roles -Priority $priority -Availability $availability -TaskTypes (Get-RouteTaskTypes -Catalog $catalog -Capabilities @($classification.Items | ForEach-Object { $_.capability }) -Metadata $parser.Metadata)
        [void]$entries.Add($entry)
    }
}

foreach ($manifest in @(Get-PluginManifests -Root (Join-Path $CodexHome 'plugins\cache'))) {
    try {
        $plugin = Get-Content -Raw -LiteralPath $manifest.FullName | ConvertFrom-Json
        $name = [string]$plugin.name
        if ([string]::IsNullOrWhiteSpace($name)) { $name = $manifest.Directory.Parent.Name }
        $description = if ($null -eq $plugin.description) { '' } else { [string]$plugin.description }
        $classification = Get-RouteClassification -Catalog $catalog -Name $name -Description $description -Triggers @() -Metadata @{}
        $availability = New-RouteAvailability -Overrides @{ cached=$true; installed=$null; configured=$null; runtime_available=$null; connected=$null; healthy=$null }
        $entry = New-IndexEntry -Name $name -Kind 'plugin' -Source $manifest.Directory.Parent.FullName -SourceRuntime 'plugin' -Path $manifest.Directory.Parent.FullName -Version $plugin.version -Description $description -Triggers @() -TriggerSource 'none' -TriggerEvidence @() -Classification $classification -RoutingRoles ([ordered]@{ 'provider'=@('tool/provider') }) -Priority 50 -Availability $availability -TaskTypes @()
        [void]$entries.Add($entry)
    } catch { }
}

$mcpNames = Get-ConfigMcpNames -Path (Join-Path $CodexHome 'config.toml')
foreach ($name in $mcpNames) {
    $record = Get-McpSnapshotRecord -Snapshot $runtimeSnapshot -Server $name
    $overrides = @{ configured=$true }
    if ($null -ne $record) {
        foreach ($field in @('runtime_visible','tools_discovered','runtime_available','healthy','startable','reachable','connected','observed_at','snapshot_id','stale')) {
            if ($record.PSObject.Properties.Name -contains $field) { $overrides[$field] = $record.$field }
        }
        if ($record.stale -eq $true) {
            $overrides.runtime_available = $null
            $overrides.healthy = $null
        }
    }
    $mappingProperty = $catalog.provider_mappings.PSObject.Properties[$name]
    $mcpCapabilities = if ($null -ne $mappingProperty) { @($mappingProperty.Value.domains) } else { @() }
    $classification = [pscustomobject]@{ Items=@($mcpCapabilities | ForEach-Object { [pscustomobject]@{ capability=$_; confidence=0.80; evidence=@('ROUTING_CATALOG.provider_mappings') } }); Audit=[ordered]@{ low_confidence=@(); single_weak_keyword=@(); name_description_conflicts=@(); parser_related=@(); suspected_misclassifications=@() } }
    $entry = New-IndexEntry -Name $name -Kind 'mcp' -Source (Join-Path $CodexHome 'config.toml') -SourceRuntime 'mcp' -Path (Join-Path $CodexHome 'config.toml') -Version $null -Description 'MCP server configured in config.toml; runtime state comes only from MCP_RUNTIME_STATUS.json.' -Triggers @() -TriggerSource 'none' -TriggerEvidence @() -Classification $classification -RoutingRoles ([ordered]@{ 'provider'=@('tool/provider') }) -Priority 50 -Availability (New-RouteAvailability -Overrides $overrides) -TaskTypes @()
    [void]$entries.Add($entry)
}

$hooksPath = Join-Path $CodexHome 'hooks.json'
if (Test-Path -LiteralPath $hooksPath -PathType Leaf) {
    try {
        $hookObject = Get-Content -Raw -LiteralPath $hooksPath | ConvertFrom-Json
        $hookRecords = @(Get-HookLeafRecords -Node $hookObject)
        $hookIndex = 0
        foreach ($hookRecord in $hookRecords) {
            $entry = New-IndexEntry -Name ("hook-$hookIndex") -Kind 'hook' -Source $hooksPath -SourceRuntime 'codex' -Path "$hooksPath#$($hookRecord.path)" -Version $null -Description 'Configured Codex lifecycle hook.' -Triggers @($hookRecord.path) -TriggerSource 'frontmatter' -TriggerEvidence @('hooks.json') -Classification ([pscustomobject]@{ Items=@(); Audit=[ordered]@{ low_confidence=@(); single_weak_keyword=@(); name_description_conflicts=@(); parser_related=@(); suspected_misclassifications=@() } }) -RoutingRoles ([ordered]@{ 'lifecycle'=@('tool/provider') }) -Priority 50 -Availability (New-RouteAvailability -Overrides @{ configured=$true }) -TaskTypes @()
            [void]$entries.Add($entry)
            $hookIndex++
        }
    } catch { }
}

$automationRoot = Join-Path $CodexHome 'automations'
if (Test-Path -LiteralPath $automationRoot -PathType Container) {
    foreach ($automation in @(Get-ChildItem -LiteralPath $automationRoot -Directory | Sort-Object Name)) {
        $automationFile = Join-Path $automation.FullName 'automation.toml'
        if (-not (Test-Path -LiteralPath $automationFile -PathType Leaf)) { continue }
        $entry = New-IndexEntry -Name $automation.Name -Kind 'automation' -Source $automationRoot -SourceRuntime 'codex' -Path $automationFile -Version $null -Description 'Configured Codex automation.' -Triggers @() -TriggerSource 'none' -TriggerEvidence @() -Classification ([pscustomobject]@{ Items=@(); Audit=[ordered]@{ low_confidence=@(); single_weak_keyword=@(); name_description_conflicts=@(); parser_related=@(); suspected_misclassifications=@() } }) -RoutingRoles ([ordered]@{ 'automation'=@('tool/provider') }) -Priority 50 -Availability (New-RouteAvailability -Overrides @{ configured=$true }) -TaskTypes @()
        [void]$entries.Add($entry)
    }
}

if ($null -ne $runtimeTools -and $null -ne $runtimeTools.tools) {
    foreach ($tool in @($runtimeTools.tools)) {
        $toolName = [string]$tool.name
        if ([string]::IsNullOrWhiteSpace($toolName)) { continue }
        $toolDescription = if ($null -eq $tool.description) { '' } else { [string]$tool.description }
        $classification = Get-RouteClassification -Catalog $catalog -Name $toolName -Description $toolDescription -Triggers @() -Metadata @{}
        $stale = if ($runtimeTools.PSObject.Properties.Name -contains 'stale') { [bool]$runtimeTools.stale } else { $true }
        $runtimeAvailable = if ($stale) { $null } else { $true }
        $availability = New-RouteAvailability -Overrides @{ discoverable_by_codex=$true; tools_discovered=$true; runtime_available=$runtimeAvailable; stale=$stale; observed_at=$runtimeTools.observed_at; snapshot_id=$runtimeTools.snapshot_id }
        $entry = New-IndexEntry -Name $toolName -Kind 'tool' -Source ([string]$runtimeTools.source) -SourceRuntime 'codex' -Path $RuntimeToolInventoryPath -Version $null -Description $toolDescription -Triggers @() -TriggerSource 'none' -TriggerEvidence @() -Classification $classification -RoutingRoles ([ordered]@{ 'runtime'=@('tool/provider') }) -Priority 50 -Availability $availability -TaskTypes @()
        [void]$entries.Add($entry)
    }
}

$entryArray = @($entries | Sort-Object kind,source_runtime,name,path)
$skillGroups = @($entryArray | Where-Object kind -eq 'skill' | Group-Object name)
$duplicateSkillNames = @($skillGroups | Where-Object { @($_.Group | Group-Object source_runtime | Where-Object Count -gt 1).Count -gt 0 } | ForEach-Object Name | Sort-Object)
$crossRuntimeMirrors = @($skillGroups | Where-Object { $_.Group.source_runtime -contains 'codex' -and $_.Group.source_runtime -contains 'mirasim' } | ForEach-Object Name | Sort-Object)
$providerCollisions = @($entryArray | Group-Object name | Where-Object { @($_.Group.kind | Select-Object -Unique | Where-Object { $_ -in @('mcp','plugin','tool') }).Count -gt 0 -and @($_.Group.kind | Select-Object -Unique | Where-Object { $_ -eq 'skill' }).Count -gt 0 } | ForEach-Object Name | Sort-Object)
$pluginVersions = @($entryArray | Where-Object kind -eq 'plugin' | Group-Object name | Where-Object { @($_.Group.version | Select-Object -Unique).Count -gt 1 } | ForEach-Object Name | Sort-Object)

$classificationAudit = [ordered]@{ low_confidence=@(); single_weak_keyword=@(); name_description_conflicts=@(); parser_related=@(); suspected_misclassifications=@(); profile_contamination=@() }
foreach ($entry in @($entryArray | Where-Object kind -eq 'skill')) {
    foreach ($field in @('low_confidence','single_weak_keyword','name_description_conflicts','parser_related','suspected_misclassifications')) {
        foreach ($item in @($entry.classification_audit.$field)) { $classificationAudit[$field] += $item }
    }
}

$profiles = [ordered]@{}
$summaryProfiles = [ordered]@{}
foreach ($property in $catalog.profiles.PSObject.Properties) {
    $profileName = $property.Name
    $set = Get-ProfileCandidateSet -Catalog $catalog -Entries $entryArray -ProfileName $profileName
    $providerCandidates = @(Get-ProviderCandidates -Catalog $catalog -Entries $entryArray -Domains @($set.domains) -ProfileName $profileName)
    $primaryDetails = @($set.primary)
    $supportingDetails = @($set.supporting)
    $verificationDetails = @($set.verification)
    $profiles[$profileName] = [ordered]@{
        intent=$set.intent
        domains=@($set.domains)
        primary_skill_candidates=@($primaryDetails | ForEach-Object name)
        supporting_skill_candidates=@($supportingDetails | ForEach-Object name)
        verification_candidates=@($verificationDetails | ForEach-Object name)
        provider_candidates=@($providerCandidates)
        primary_candidate_details=$primaryDetails
        supporting_candidate_details=$supportingDetails
        verification_candidate_details=$verificationDetails
    }
    $summaryProfiles[$profileName] = [ordered]@{
        intent=$set.intent
        domains=@($set.domains)
        primary_skill_candidates=@($primaryDetails | ForEach-Object name)
        supporting_skill_candidates=@($supportingDetails | ForEach-Object name)
        verification_candidates=@($verificationDetails | ForEach-Object name)
        provider_candidates=@($providerCandidates)
    }
    $forbiddenRules = $catalog.profile_contamination.PSObject.Properties[$profileName]
    if ($null -ne $forbiddenRules) {
        $profileCandidates = @(
            foreach ($candidate in $primaryDetails) { [pscustomobject]@{ item=$candidate; role='primary' } }
            foreach ($candidate in $supportingDetails) { [pscustomobject]@{ item=$candidate; role='supporting' } }
            foreach ($candidate in $verificationDetails) { [pscustomobject]@{ item=$candidate; role='verification' } }
        )
        foreach ($candidateRecord in $profileCandidates) {
            $candidate = $candidateRecord.item
            $entryForAudit = @($entryArray | Where-Object { $_.kind -eq 'skill' -and $_.name -eq $candidate.name }) | Select-Object -First 1
            if ($null -ne $entryForAudit) {
                $forbidden = Test-ProfileForbidden -Catalog $catalog -ProfileName $profileName -Entry $entryForAudit -Role $candidateRecord.role
                if ($forbidden.forbidden) { $classificationAudit.profile_contamination += [pscustomobject]@{ profile=$profileName; name=$candidate.name; reason=$forbidden.reason } }
            }
        }
    }
}

$entryCounts = [ordered]@{}
foreach ($kind in @('skill','plugin','mcp','tool','hook','automation')) { $entryCounts[$kind] = @($entryArray | Where-Object kind -eq $kind).Count }
$entryCounts.total = $entryArray.Count
$stats = [ordered]@{
    skill_count=$parserStats.skill_count
    description_normal_count=$parserStats.description_normal_count
    description_empty_count=$parserStats.description_empty_count
    description_parser_failure_count=$parserStats.description_parser_failure_count
    trigger_extracted_count=$parserStats.trigger_extracted_count
    trigger_empty_count=$parserStats.trigger_empty_count
    explicit_trigger_count=$parserStats.explicit_trigger_count
    derived_trigger_count=$parserStats.derived_trigger_count
    fallback_description_count=$parserStats.fallback_description_count
    empty_trigger_count=$parserStats.empty_trigger_count
    unclassified_count=@($entryArray | Where-Object { $_.kind -eq 'skill' -and @($_.capabilities).Count -eq 0 }).Count
    low_confidence_count=@($classificationAudit.low_confidence).Count
    entry_counts=$entryCounts
}

$runtimeNotes = New-Object System.Collections.Generic.List[string]
if ($null -eq $runtimeSnapshot) { $runtimeNotes.Add('MCP_RUNTIME_STATUS.json was unavailable; MCP runtime fields remain unknown.') }
if ($null -eq $runtimeTools) { $runtimeNotes.Add('RUNTIME_TOOLS.json was unavailable; tool runtime fields remain unknown.') }
elseif ($runtimeTools.PSObject.Properties.Name -notcontains 'observed_at') { $runtimeNotes.Add('RUNTIME_TOOLS.json lacks observed_at metadata and is treated as stale/unknown.') }
if (@($entryArray | Where-Object { $_.kind -eq 'skill' -and $_.source_runtime -eq 'mirasim' }).Count -gt 0) { $runtimeNotes.Add('Mirasim-only skills are retained in Full Index but excluded from native Codex candidate selection unless discoverability is proven.') }

$generatedAt = (Get-Date).ToUniversalTime().ToString('o')
$full = [ordered]@{
    schema_version='2.1'
    index_type='full'
    generated_at=$generatedAt
    catalog_path=[System.IO.Path]::GetFullPath($CatalogPath)
    statistics=$stats
    duplicate_categories=[ordered]@{ duplicate_skill_names=$duplicateSkillNames; cross_runtime_skill_mirrors=$crossRuntimeMirrors; provider_name_collisions=$providerCollisions; plugin_version_duplicates=$pluginVersions }
    classification_audit=$classificationAudit
    runtime_truth_notes=@($runtimeNotes)
    profiles=$profiles
    entries=$entryArray
}

$summaryMcp = @($entryArray | Where-Object kind -eq 'mcp' | ForEach-Object {
    [ordered]@{ name=$_.name; configured=$_.availability.configured; runtime_visible=$_.availability.runtime_visible; tools_discovered=$_.availability.tools_discovered; runtime_available=$_.availability.runtime_available; healthy=$_.availability.healthy; stale=$_.availability.stale; observed_at=$_.availability.observed_at }
})
$skillRuntimeRecords = @($entryArray | Where-Object kind -eq 'skill' | ForEach-Object {
    [ordered]@{
        name=$_.name
        kind=$_.kind
        source_runtime=$_.source_runtime
        discoverable_by_codex=$_.availability.discoverable_by_codex
        stale=$_.availability.stale
        runtime_available=$_.availability.runtime_available
        eligible_for_codex_route=($_.kind -eq 'skill' -and $_.source_runtime -eq 'codex' -and $_.availability.discoverable_by_codex -eq $true -and $_.availability.stale -ne $true)
    }
})
$summary = [ordered]@{
    schema_version='2.1'
    index_type='summary'
    generated_at=$generatedAt
    catalog_path=[System.IO.Path]::GetFullPath($CatalogPath)
    full_path=[System.IO.Path]::GetFullPath($FullOutputPath)
    statistics=$stats
    profiles=$summaryProfiles
    core_skills=@($catalog.qa_rules.required_sample_skills | Select-Object -First 24)
    core_mcp_servers=$summaryMcp
    skill_runtime_filter=[ordered]@{
        rule='Only entries with kind=skill, source_runtime=codex, discoverable_by_codex=true, and stale!=true may enter the strict Codex route; Mirasim-only entries remain external/unknown.'
        records=$skillRuntimeRecords
    }
    duplicate_category_counts=[ordered]@{ duplicate_skill_names=$duplicateSkillNames.Count; cross_runtime_skill_mirrors=$crossRuntimeMirrors.Count; provider_name_collisions=$providerCollisions.Count; plugin_version_duplicates=$pluginVersions.Count }
    classification_audit_counts=[ordered]@{ low_confidence=@($classificationAudit.low_confidence).Count; single_weak_keyword=@($classificationAudit.single_weak_keyword).Count; name_description_conflicts=@($classificationAudit.name_description_conflicts).Count; parser_related=@($classificationAudit.parser_related).Count; suspected_misclassifications=@($classificationAudit.suspected_misclassifications).Count; profile_contamination=@($classificationAudit.profile_contamination).Count }
}
$compat = [ordered]@{ schema_version='2.1'; index_type='compatibility-pointer'; generated_at=$generatedAt; summary_path=[System.IO.Path]::GetFullPath($SummaryOutputPath); full_path=[System.IO.Path]::GetFullPath($FullOutputPath); counts=$entryCounts }

$fullJson = $full | ConvertTo-Json -Depth 30
$summaryJson = $summary | ConvertTo-Json -Depth 30
$compatJson = $compat | ConvertTo-Json -Depth 10
@($fullJson,$summaryJson,$compatJson) | ForEach-Object { if ([string]::IsNullOrWhiteSpace($_)) { throw 'Generated JSON was empty.' } }
foreach ($json in @($fullJson,$summaryJson,$compatJson)) { $null = $json | ConvertFrom-Json }

$lockPath = Join-Path $CodexHome '.workflow-router-index.lock'
$lockStream = $null
$deadline = (Get-Date).AddSeconds($LockTimeoutSeconds)
try {
    while ($null -eq $lockStream) {
        try { $lockStream = New-Object System.IO.FileStream($lockPath, ([System.IO.FileMode]::CreateNew), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::None)) }
        catch [System.IO.IOException] {
            if ((Get-Date) -ge $deadline) { throw "Could not acquire Router index lock within $LockTimeoutSeconds seconds: $lockPath" }
            Start-Sleep -Milliseconds 250
        }
    }
    Write-RouteAtomicText -Path $FullOutputPath -Content $fullJson
    Write-RouteAtomicText -Path $SummaryOutputPath -Content $summaryJson
    Write-RouteAtomicText -Path $CompatibilityOutputPath -Content $compatJson
} finally {
    if ($null -ne $lockStream) { $lockStream.Dispose() }
    if (Test-Path -LiteralPath $lockPath -PathType Leaf) { [System.IO.File]::Delete($lockPath) }
}

Write-Output 'GENERATION COMPLETE:'
Write-Output "  FULL:    $FullOutputPath ($([System.Text.Encoding]::UTF8.GetByteCount($fullJson)) bytes)"
Write-Output "  SUMMARY: $SummaryOutputPath ($([System.Text.Encoding]::UTF8.GetByteCount($summaryJson)) bytes)"
Write-Output "  COMPAT:  $CompatibilityOutputPath ($([System.Text.Encoding]::UTF8.GetByteCount($compatJson)) bytes)"
Write-Output "  ENTRIES: $($entryArray.Count), PARSER_FAILURES: $($parserStats.description_parser_failure_count)"
