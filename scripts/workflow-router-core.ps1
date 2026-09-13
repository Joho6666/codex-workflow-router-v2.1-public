# Shared, side-effect-free Workflow Router 2.1 core.
# All routing policy comes from ROUTING_CATALOG.json; callers only provide prompt and indexes.

function Read-WorkflowRouterJson {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required Router JSON is missing: $Path"
    }
    return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -DateKind String)
}

function Get-ConfiguredMcpNames {
    param([Parameter(Mandatory=$true)][string]$ConfigPath)
    $names = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return @() }
    foreach ($line in Get-Content -LiteralPath $ConfigPath) {
        $match = [regex]::Match($line, '^\[mcp_servers\.([^\.\]]+)(?:\.[^\.\]]+)?\]$')
        if ($match.Success -and -not ($names -contains $match.Groups[1].Value)) { $names.Add($match.Groups[1].Value) }
    }
    return @($names)
}

function Get-WorkflowRouterCatalog {
    param([string]$CatalogPath = '')
    if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
        $CatalogPath = Join-Path $PSScriptRoot '..\ROUTING_CATALOG.json'
    }
    return Read-WorkflowRouterJson -Path ([System.IO.Path]::GetFullPath($CatalogPath))
}

function ConvertFrom-RouteScalar {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) {
        $text = $Value.Trim()
        if ($text -eq '' -or $text -eq 'null' -or $text -eq '~') { return $null }
        if (($text.StartsWith('"') -and $text.EndsWith('"')) -or ($text.StartsWith("'") -and $text.EndsWith("'"))) {
            return $text.Substring(1, $text.Length - 2)
        }
        return $text
    }
    return [string]$Value
}

function Get-RouteStableUnique {
    param(
        [AllowNull()][object]$Items,
        [string]$Property = ''
    )
    $seen = @{}
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        $key = if ([string]::IsNullOrWhiteSpace($Property)) { [string]$item } else { [string]$item.$Property }
        if ([string]::IsNullOrWhiteSpace($key) -or $seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [void]$result.Add($item)
    }
    return $result.ToArray()
}

function ConvertTo-RouteStringArray {
    param([AllowNull()][object]$Value)
    $items = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Value) { return @() }
    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        foreach ($item in $Value) {
            $scalar = ConvertFrom-RouteScalar $item
            if ($null -ne $scalar -and $scalar.Trim() -ne '') { $items.Add($scalar.Trim()) }
        }
        return @(Get-RouteStableUnique -Items $items)
    }
    $text = (ConvertFrom-RouteScalar $Value)
    if ($null -eq $text) { return @() }
    if ($text.StartsWith('[') -and $text.EndsWith(']')) { $text = $text.Substring(1, $text.Length - 2) }
    foreach ($part in ($text -split ',')) {
        $scalar = ConvertFrom-RouteScalar $part
        if ($null -ne $scalar -and $scalar.Trim() -ne '') { $items.Add($scalar.Trim()) }
    }
    return @(Get-RouteStableUnique -Items $items)
}

function Get-RouteIndent {
    param([string]$Line)
    if ($null -eq $Line) { return 0 }
    $match = [regex]::Match($Line, '^(\s*)')
    return $match.Groups[1].Value.Length
}

function Join-RouteBlockScalar {
    param([string[]]$Lines, [string]$Indicator)
    $nonBlank = @($Lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $baseIndent = 0
    if ($nonBlank.Count -gt 0) { $baseIndent = @($nonBlank | ForEach-Object { Get-RouteIndent $_ } | Measure-Object -Minimum).Minimum }
    $normalized = @($Lines | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_)) { '' }
        elseif ($_.Length -ge $baseIndent) { $_.Substring($baseIndent) }
        else { $_.Trim() }
    })
    $folded = $Indicator.StartsWith('>')
    $result = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $normalized.Count; $i++) {
        $line = $normalized[$i]
        if (-not $folded) { $result.Add($line); continue }
        if ($line -eq '') { $result.Add(''); continue }
        if ($result.Count -eq 0 -or $result[$result.Count - 1] -eq '') { $result.Add($line) }
        else { $result[$result.Count - 1] = $result[$result.Count - 1] + ' ' + $line }
    }
    $text = ($result -join "`n")
    if (-not $Indicator.Contains('+')) { $text = $text.TrimEnd("`r", "`n") }
    if ($Indicator.Contains('+')) { $text = $text.TrimEnd("`r", "`n") + "`n" }
    return $text
}

function Get-RouteFrontMatter {
    param([Parameter(Mandatory=$true)][string]$Path)
    $raw = [System.IO.File]::ReadAllText($Path)
    $lines = @($raw -split '\r?\n')
    if ($lines.Count -gt 0) { $lines[0] = $lines[0].TrimStart([char]0xFEFF) }
    $metadata = [ordered]@{}
    $body = @()
    $errors = New-Object System.Collections.Generic.List[string]
    if ($lines.Count -eq 0 -or $lines[0].Trim() -ne '---') {
        return [pscustomobject]@{ Metadata=$metadata; Body=$lines; DescriptionPresent=$false; DescriptionParserFailure=$false; ParserErrors=@() }
    }
    $closing = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -in @('---', '...')) { $closing = $i; break }
    }
    if ($closing -lt 0) {
        $errors.Add('frontmatter closing delimiter not found')
        return [pscustomobject]@{ Metadata=$metadata; Body=@(); DescriptionPresent=$false; DescriptionParserFailure=$true; ParserErrors=@($errors) }
    }
    for ($i = 1; $i -lt $closing; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ((Get-RouteIndent $line) -gt 0) { continue }
        $match = [regex]::Match($line, '^(\s*)([^:\s][^:]*):(?:\s*(.*))?$')
        if (-not $match.Success) { $errors.Add("unparsed frontmatter line $($i + 1)"); continue }
        $key = $match.Groups[2].Value
        $value = if ($match.Groups[3].Success) { $match.Groups[3].Value.Trim() } else { '' }
        if ($value -match '^[|>][+\-]?$') {
            $block = New-Object System.Collections.Generic.List[string]
            $keyIndent = $match.Groups[1].Value.Length
            $j = $i + 1
            while ($j -lt $closing) {
                $next = $lines[$j]
                if ([string]::IsNullOrWhiteSpace($next)) { $block.Add(''); $j++; continue }
                if ((Get-RouteIndent $next) -le $keyIndent) { break }
                $block.Add($next)
                $j++
            }
            $metadata[$key] = Join-RouteBlockScalar -Lines @($block) -Indicator $value
            $i = $j - 1
            continue
        }
        if ($value -eq '') {
            $list = New-Object System.Collections.Generic.List[string]
            $j = $i + 1
            while ($j -lt $closing) {
                $next = $lines[$j]
                if ($next -match '^\s*-\s*(.+)$') { $list.Add((ConvertFrom-RouteScalar $Matches[1])); $j++; continue }
                if ([string]::IsNullOrWhiteSpace($next)) { $j++; continue }
                break
            }
            if ($list.Count -gt 0) { $metadata[$key] = @($list); $i = $j - 1 }
            else { $metadata[$key] = $null }
            continue
        }
        $metadata[$key] = ConvertFrom-RouteScalar $value
    }
    if ($closing + 1 -lt $lines.Count) { $body = @($lines[($closing + 1)..($lines.Count - 1)]) }
    $descriptionPresent = $metadata.Contains('description')
    return [pscustomobject]@{ Metadata=$metadata; Body=$body; DescriptionPresent=$descriptionPresent; DescriptionParserFailure=($errors.Count -gt 0); ParserErrors=@($errors) }
}

function Get-RouteMarkdownSection {
    param([string[]]$Body, [string[]]$Headings)
    $start = -1
    for ($i = 0; $i -lt $Body.Count; $i++) {
        if ($Body[$i] -match '^\s*#{1,6}\s+(.+?)\s*$') {
            $heading = $Matches[1].Trim().ToLowerInvariant()
            if (@($Headings | ForEach-Object { $_.ToLowerInvariant() }) -contains $heading) { $start = $i + 1; break }
        }
    }
    if ($start -lt 0) { return @() }
    $result = New-Object System.Collections.Generic.List[string]
    for ($i = $start; $i -lt $Body.Count; $i++) {
        if ($Body[$i] -match '^\s*#{1,6}\s+') { break }
        $text = $Body[$i].Trim()
        if ($text -match '^[-*+]\s+(.+)$') { $text = $Matches[1].Trim() }
        if ($text -ne '') { $result.Add($text) }
    }
    return @($result)
}

function Get-RouteTriggerInfo {
    param($Parser)
    $explicit = ConvertTo-RouteStringArray $Parser.Metadata['trigger']
    if ($explicit.Count -eq 0) { $explicit = ConvertTo-RouteStringArray $Parser.Metadata['triggers'] }
    if ($explicit.Count -gt 0) {
        return [pscustomobject]@{ values=@($explicit); source='frontmatter'; evidence=@('frontmatter trigger/triggers'); explicit=$true; derived=$false; fallback=$false }
    }
    $description = [string]$Parser.Metadata['description']
    $descriptionText = ConvertTo-RouteText $description
    $useWhen = [regex]::Match($descriptionText, '(?i)(use\s+(?:this\s+)?skill\s+when\s+.+?)(?:\.\s|$)')
    if ($useWhen.Success) {
        return [pscustomobject]@{ values=@($useWhen.Groups[1].Value.Trim()); source='description_use_when'; evidence=@('description contains Use when'); explicit=$false; derived=$true; fallback=$false }
    }
    $lines = @($description -split '\r?\n')
    $useLine = @($lines | Where-Object { $_ -match '(?i)^\s*(?:[-*]\s*)?(?:use\s+(?:this\s+)?skill\s+when|use\s+when|when\s+the\s+user|当用户|当需要)' } | Select-Object -First 1)
    if ($useLine.Count -gt 0) {
        return [pscustomobject]@{ values=@($useLine[0].Trim()); source='description_use_when'; evidence=@('description use-when line'); explicit=$false; derived=$true; fallback=$false }
    }
    $section = Get-RouteMarkdownSection -Body @($Parser.Body) -Headings @('when to use', 'trigger', '适用场景', '触发条件')
    if ($section.Count -gt 0) {
        return [pscustomobject]@{ values=@(($section -join "`n")); source=if ($section[0] -match '(?i)trigger|适用|触发') { 'trigger_section' } else { 'when_to_use_section' }; evidence=@('markdown section body'); explicit=$false; derived=$true; fallback=$false }
    }
    if (-not [string]::IsNullOrWhiteSpace($description)) {
        return [pscustomobject]@{ values=@($description.Trim()); source='fallback_description'; evidence=@('description fallback without trigger evidence'); explicit=$false; derived=$false; fallback=$true }
    }
    return [pscustomobject]@{ values=@(); source='none'; evidence=@(); explicit=$false; derived=$false; fallback=$false }
}

function Get-ClassificationRules {
    param($Catalog)
    $rules = [ordered]@{}
    foreach ($property in $Catalog.domains.PSObject.Properties) { $rules[$property.Name] = $property.Value }
    foreach ($property in $Catalog.capabilities.PSObject.Properties) {
        if (-not $rules.Contains($property.Name)) { $rules[$property.Name] = $property.Value }
    }
    return $rules
}

function Get-RouteClassification {
    param($Catalog, [string]$Name, [string]$Description, [string[]]$Triggers, $Metadata, [bool]$ParserFailure=$false)
    $text = ConvertTo-RouteText ("$Name $Description $($Triggers -join ' ')")
    $tokens = Get-RouteTokens $text
    $items = New-Object System.Collections.Generic.List[object]
    $audit = [ordered]@{ low_confidence=@(); single_weak_keyword=@(); name_description_conflicts=@(); parser_related=@(); suspected_misclassifications=@() }
    $overrideProp = $Catalog.classification_overrides.PSObject.Properties[$Name]
    $override = if ($null -ne $overrideProp) { $overrideProp.Value } else { $null }
    $explicit = ConvertTo-RouteStringArray $Metadata['capabilities']
    $forced = if ($null -ne $override) { ConvertTo-RouteStringArray $override.force_capabilities } else { @() }
    $excluded = if ($null -ne $override) { ConvertTo-RouteStringArray $override.exclude_capabilities } else { @() }
    foreach ($cap in @(Get-RouteStableUnique -Items @($explicit + $forced))) {
        if ($excluded -contains $cap) { continue }
        $items.Add([pscustomobject]@{ capability=$cap; confidence=1.0; evidence=@('explicit or catalog override') })
    }
    $rules = Get-ClassificationRules $Catalog
    foreach ($cap in $rules.Keys) {
        if ($excluded -contains $cap -or @($items | ForEach-Object { $_.capability }) -contains $cap) { continue }
        $rule = $rules[$cap]
        $strong = @(Get-MatchedRouteTerms -Text $text -Tokens $tokens -Terms @($rule.strong_terms))
        $weak = @(Get-MatchedRouteTerms -Text $text -Tokens $tokens -Terms @($rule.weak_terms))
        if ($strong.Count -ge 2) {
            $items.Add([pscustomobject]@{ capability=$cap; confidence=0.95; evidence=@("strong: $($strong -join ', ')") })
        } elseif ($strong.Count -eq 1) {
            $items.Add([pscustomobject]@{ capability=$cap; confidence=0.85; evidence=@("strong: $($strong -join ', ')") })
        } elseif ($weak.Count -ge 2) {
            $items.Add([pscustomobject]@{ capability=$cap; confidence=0.70; evidence=@("weak-combination: $($weak -join ', ')") })
        } elseif ($weak.Count -eq 1) {
            $audit.single_weak_keyword += [pscustomobject]@{ name=$Name; capability=$cap; keyword=$weak[0] }
        }
    }
    if ($items.Count -eq 0) { $audit.low_confidence += [pscustomobject]@{ name=$Name; reason='no strong or combined weak evidence' } }
    if ($ParserFailure) { $audit.parser_related += [pscustomobject]@{ name=$Name; reason='frontmatter parser reported an error' } }
    return [pscustomobject]@{ Items=@($items | Sort-Object @{Expression='confidence';Descending=$true}, @{Expression='capability';Descending=$false}); Audit=$audit }
}

function Get-RouteTaskTypes {
    param($Catalog, [string[]]$Capabilities, $Metadata)
    $explicit = ConvertTo-RouteStringArray $Metadata['task_types']
    if ($explicit.Count -gt 0) { return @($explicit) }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($cap in @($Capabilities)) {
        $prop = $Catalog.capabilities.PSObject.Properties[$cap]
        if ($null -eq $prop) { $prop = $Catalog.domains.PSObject.Properties[$cap] }
        if ($null -ne $prop) { foreach ($task in @(ConvertTo-RouteStringArray $prop.Value.task_types)) { $out.Add($task) } }
    }
    return @(Get-RouteStableUnique -Items $out)
}

function Get-RouteRoleBindings {
    param($Catalog, [string]$Name, $Metadata)
    $result = [ordered]@{}
    $catalogProperty = $Catalog.skill_role_bindings.PSObject.Properties[$Name]
    if ($null -ne $catalogProperty) {
        foreach ($property in $catalogProperty.Value.PSObject.Properties) { $result[$property.Name] = @(ConvertTo-RouteStringArray $property.Value) }
    }
    return $result
}

function Get-RouteUnionRoles {
    param($RoutingRoles)
    $roles = New-Object System.Collections.Generic.List[string]
    foreach ($property in $RoutingRoles.Keys) { foreach ($role in @($RoutingRoles[$property])) { $roles.Add($role) } }
    return @(Get-RouteStableUnique -Items $roles)
}

function New-RouteAvailability {
    param([hashtable]$Overrides=@{})
    $result = [ordered]@{ cached=$null; installed=$null; configured=$null; discoverable_by_codex=$null; startable=$null; reachable=$null; tools_discovered=$null; runtime_available=$null; connected=$null; healthy=$null; stale=$null; observed_at=$null; snapshot_id=$null }
    foreach ($key in $Overrides.Keys) { $result[$key] = $Overrides[$key] }
    return $result
}

function Get-McpSnapshotRecord {
    param($Snapshot, [string]$Server)
    if ($null -eq $Snapshot) { return $null }
    return @($Snapshot.servers | Where-Object { $_.server -eq $Server }) | Select-Object -First 1
}

function Test-RouteSnapshotStale {
    param($Snapshot, [string]$ObservedAt, [int]$DefaultSeconds=21600)
    if ($null -ne $Snapshot -and $Snapshot.PSObject.Properties.Name -contains 'stale' -and [bool]$Snapshot.stale) { return $true }
    if ([string]::IsNullOrWhiteSpace($ObservedAt)) { return $true }
    try {
        $age = ((Get-Date).ToUniversalTime() - ([datetime]::Parse($ObservedAt).ToUniversalTime())).TotalSeconds
        return ($age -gt $DefaultSeconds)
    } catch { return $true }
}

function Write-RouteAtomicText {
    param([Parameter(Mandatory=$true)][string]$Path, [Parameter(Mandatory=$true)][string]$Content)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $tempPath = "$Path.$PID.$([guid]::NewGuid().ToString('N')).tmp"
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tempPath, $Content, $utf8)
    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $backupPath = "$Path.$PID.$([guid]::NewGuid().ToString('N')).bak"
            [System.IO.File]::Replace($tempPath, $Path, $backupPath)
            if (Test-Path -LiteralPath $backupPath -PathType Leaf) { [System.IO.File]::Delete($backupPath) }
        }
        else { [System.IO.File]::Move($tempPath, $Path) }
    } catch {
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) { [System.IO.File]::Delete($tempPath) }
        throw
    }
}

function ConvertTo-RouteText {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $value = $Text.ToLowerInvariant()
    $value = $value -replace '[\r\n\t]+', ' '
    return (($value -replace '\s+', ' ').Trim())
}

function Get-RouteTokens {
    param([string]$Text)
    $normalized = ConvertTo-RouteText $Text
    $tokens = New-Object System.Collections.Generic.List[string]
    foreach ($match in [regex]::Matches($normalized, '[a-z0-9]+(?:[._-][a-z0-9]+)*|[\p{IsCJKUnifiedIdeographs}]+')) {
        $value = $match.Value
        $tokens.Add($value)
        if ($value -match '[._-]') {
            foreach ($part in ($value -split '[._-]+')) {
                if (-not [string]::IsNullOrWhiteSpace($part)) { $tokens.Add($part) }
            }
        }
    }
    return @(Get-RouteStableUnique -Items $tokens)
}

function Test-RouteTerm {
    param([string]$Text, [string[]]$Tokens, [string]$Term)
    $needle = ConvertTo-RouteText $Term
    if ([string]::IsNullOrWhiteSpace($needle)) { return $false }
    if ($needle -match '\s' -or $needle -match '[\p{IsCJKUnifiedIdeographs}]') {
        return $Text.Contains($needle, [System.StringComparison]::OrdinalIgnoreCase)
    }
    return @($Tokens) -contains $needle
}

function Get-MatchedRouteTerms {
    param([string]$Text, [string[]]$Tokens, [string[]]$Terms)
    $matched = New-Object System.Collections.Generic.List[string]
    foreach ($term in @($Terms)) {
        if (Test-RouteTerm -Text $Text -Tokens $Tokens -Term ([string]$term)) { $matched.Add([string]$term) }
    }
    return @($matched)
}

function Get-RouteIntent {
    param($Catalog, [string]$Prompt)
    $text = ConvertTo-RouteText $Prompt
    $tokens = Get-RouteTokens $Prompt
    $ranked = New-Object System.Collections.Generic.List[object]
    foreach ($property in $Catalog.intents.PSObject.Properties) {
        $matches = Get-MatchedRouteTerms -Text $text -Tokens $tokens -Terms @($property.Value.terms)
        $score = 0
        foreach ($match in $matches) { $score += 10 + $match.Length }
        if ($matches.Count -gt 0) {
            $ranked.Add([pscustomobject]@{ name=$property.Name; score=$score; matches=@($matches) })
        }
    }
    if ($ranked.Count -eq 0) {
        return [pscustomobject]@{ name='development'; score=0; matches=@(); confidence=0.35 }
    }
    $best = @($ranked | Sort-Object @{Expression='score';Descending=$true}, @{Expression='name';Descending=$false})[0]
    $confidence = [math]::Min(0.99, [math]::Max(0.45, 0.45 + ($best.score / 100.0)))
    return [pscustomobject]@{ name=$best.name; score=$best.score; matches=@($best.matches); confidence=$confidence }
}

function Get-RouteDomains {
    param($Catalog, [string]$Prompt)
    $text = ConvertTo-RouteText $Prompt
    $tokens = Get-RouteTokens $Prompt
    $ranked = New-Object System.Collections.Generic.List[object]
    foreach ($property in $Catalog.domains.PSObject.Properties) {
        $definition = $property.Value
        $strong = Get-MatchedRouteTerms -Text $text -Tokens $tokens -Terms @($definition.strong_terms)
        $weak = Get-MatchedRouteTerms -Text $text -Tokens $tokens -Terms @($definition.weak_terms)
        $score = ($strong.Count * 12) + ($weak.Count * 3)
        if ($strong.Count -gt 0 -or $weak.Count -ge 2) {
            $ranked.Add([pscustomobject]@{ name=$property.Name; score=$score; strong=@($strong); weak=@($weak) })
        }
    }
    $ordered = @($ranked | Sort-Object @{Expression='score';Descending=$true}, @{Expression='name';Descending=$false})
    $domains = @($ordered | ForEach-Object { $_.name })
    $explicitKeep = @($Catalog.domain_selection.keep_if_explicit | Where-Object { Test-RouteTerm -Text $text -Tokens $tokens -Term $_ })
    foreach ($suppressor in $Catalog.domain_selection.suppress.PSObject.Properties) {
        if ($domains -notcontains $suppressor.Name) { continue }
        foreach ($suppressed in @($suppressor.Value)) {
            if ($domains -notcontains $suppressed) { continue }
            $retained = @($Catalog.domain_selection.retain_pairs | Where-Object { (@($_) -contains $suppressor.Name) -and (@($_) -contains $suppressed) }).Count -gt 0
            if (-not $retained -and $explicitKeep -notcontains $suppressed) { $domains = @($domains | Where-Object { $_ -ne $suppressed }) }
        }
    }
    if ($domains.Count -gt [int]$Catalog.domain_selection.max_domains) { $domains = @($domains | Select-Object -First ([int]$Catalog.domain_selection.max_domains)) }
    if ($domains.Count -eq 0) { $domains = @('unknown') }
    return [pscustomobject]@{ domains=$domains; evidence=$ordered }
}

function Get-RouteScale {
    param($Catalog, [string]$Prompt, [string]$Intent, [string[]]$Domains)
    $text = ConvertTo-RouteText $Prompt
    $tokens = Get-RouteTokens $Prompt
    $fastRule = @($Catalog.scale_rules | Where-Object { $_.scale -eq 'FAST' }) | Select-Object -First 1
    $deepRule = @($Catalog.scale_rules | Where-Object { $_.scale -eq 'DEEP' }) | Select-Object -First 1
    $fastMatches = if ($null -ne $fastRule) { @(Get-MatchedRouteTerms -Text $text -Tokens $tokens -Terms @($fastRule.terms)) } else { @() }
    $deepMatches = if ($null -ne $deepRule) { @(Get-MatchedRouteTerms -Text $text -Tokens $tokens -Terms @($deepRule.terms)) } else { @() }
    $deepDomainMatch = @($Domains | Where-Object { @($deepRule.deep_domains) -contains $_ }).Count -gt 0
    if ($Intent -eq 'maintenance' -and $deepMatches.Count -eq 0) {
        return [pscustomobject]@{ scale='FAST'; evidence=@($fastMatches); reason='maintenance task without deep-scope signal' }
    }
    if ($deepMatches.Count -gt 0 -or $deepDomainMatch) {
        return [pscustomobject]@{ scale='DEEP'; evidence=@($deepMatches); reason='deep terms or engineering domain signal' }
    }
    if ($fastMatches.Count -gt 0) {
        return [pscustomobject]@{ scale='FAST'; evidence=@($fastMatches); reason='isolated small change signal' }
    }
    return [pscustomobject]@{ scale='STANDARD'; evidence=@(); reason='ordinary task scope' }
}

function Get-RouteRisk {
    param($Catalog, [string]$Prompt)
    $text = ConvertTo-RouteText $Prompt
    $tokens = Get-RouteTokens $Prompt
    $rank = @{ LOW=0; MEDIUM=1; HIGH=2; CRITICAL=3 }
    $best = [pscustomobject]@{ level='LOW'; score=0; matches=@() }
    foreach ($rule in @($Catalog.risk_rules)) {
        $matches = Get-MatchedRouteTerms -Text $text -Tokens $tokens -Terms @($rule.terms)
        if ($matches.Count -eq 0) { continue }
        $score = $rank[[string]$rule.level] * 100 + $matches.Count
        if ($score -gt $best.score) { $best = [pscustomobject]@{ level=[string]$rule.level; score=$score; matches=@($matches); rule=$rule.id } }
    }
    return [pscustomobject]@{ risk=$best.level; evidence=@($best.matches); rule=$best.rule }
}

function Get-RouteProfile {
    param($Catalog, [string[]]$Domains, [string]$Intent)
    $scores = New-Object System.Collections.Generic.List[object]
    foreach ($property in $Catalog.profiles.PSObject.Properties) {
        $profile = $property.Name
        $definition = $property.Value
        $matched = @($Domains | Where-Object { @($definition.domains) -contains $_ })
        $score = $matched.Count * 100
        if ($matched -contains $profile) { $score += 25 }
        if (@($definition.intents) -contains $Intent) { $score += 10 }
        if ($score -gt 0) { $scores.Add([pscustomobject]@{ name=$profile; score=$score; matched=@($matched) }) }
    }
    if ($scores.Count -eq 0) { return [pscustomobject]@{ name='development'; evidence=@() } }
    $best = @($scores | Sort-Object @{Expression='score';Descending=$true}, @{Expression='name';Descending=$false})[0]
    return [pscustomobject]@{ name=$best.name; evidence=@($best) }
}

function Get-RouteContextKeys {
    param([string]$Intent, [string[]]$Domains)
    $keys = New-Object System.Collections.Generic.List[string]
    $keys.Add($Intent)
    foreach ($domain in @($Domains)) {
        if (-not [string]::IsNullOrWhiteSpace($domain) -and $domain -ne 'unknown') { $keys.Add($domain) }
    }
    if ($Intent -eq 'bugfix') { $keys.Add('debugging') }
    return @(Get-RouteStableUnique -Items $keys)
}

function Get-ContextualRoles {
    param($Catalog, $Entry, [string[]]$ContextKeys)
    $roles = New-Object System.Collections.Generic.List[string]
    $bindingProperty = $Catalog.skill_role_bindings.PSObject.Properties[$Entry.name]
    if ($null -ne $bindingProperty) {
        foreach ($key in @($ContextKeys)) {
            $roleProperty = $bindingProperty.Value.PSObject.Properties[$key]
            if ($null -ne $roleProperty) {
                foreach ($role in @($roleProperty.Value)) { $roles.Add([string]$role) }
            }
        }
    }
    return @(Get-RouteStableUnique -Items $roles)
}

function Test-CodexSkillRuntime {
    param($Entry)
    if ($Entry.kind -ne 'skill') { return $false }
    if ($Entry.availability.discoverable_by_codex -ne $true) { return $false }
    if ($Entry.source_runtime -ne 'codex' -and $Entry.availability.runtime_available -ne $true) { return $false }
    if ($Entry.availability.stale -eq $true) { return $false }
    return $true
}

function Get-EntrySearchText {
    param($Entry)
    $triggerText = @($Entry.triggers | ForEach-Object { [string]$_ }) -join ' '
    return (ConvertTo-RouteText ("$($Entry.name) $($Entry.description) $triggerText"))
}

function Get-EntrySignalMatches {
    param($Catalog, $Entry, [string[]]$Domains)
    $text = Get-EntrySearchText $Entry
    $tokens = Get-RouteTokens $text
    $strong = New-Object System.Collections.Generic.List[string]
    $weak = New-Object System.Collections.Generic.List[string]
    foreach ($domain in @($Domains)) {
        $prop = $Catalog.domains.PSObject.Properties[$domain]
        if ($null -eq $prop) { continue }
        foreach ($term in @(Get-MatchedRouteTerms -Text $text -Tokens $tokens -Terms @($prop.Value.strong_terms))) { $strong.Add(($domain + ':' + $term)) }
        foreach ($term in @(Get-MatchedRouteTerms -Text $text -Tokens $tokens -Terms @($prop.Value.weak_terms))) { $weak.Add(($domain + ':' + $term)) }
    }
    return [pscustomobject]@{ strong=@($strong); weak=@($weak) }
}

function Test-ProfileForbidden {
    param($Catalog, [string]$ProfileName, $Entry, [string]$Role = '')
    $property = $Catalog.profile_contamination.PSObject.Properties[$ProfileName]
    if ($null -eq $property) { return [pscustomobject]@{ forbidden=$false; reason='' } }
    $rules = $property.Value
    if (@($rules.forbidden_names) -contains $Entry.name) { return [pscustomobject]@{ forbidden=$true; reason="forbidden name: $($Entry.name)" } }
    if ($Role -eq 'primary' -and @($rules.forbidden_primary_names) -contains $Entry.name) { return [pscustomobject]@{ forbidden=$true; reason="forbidden primary name: $($Entry.name)" } }
    foreach ($cap in @($Entry.capabilities)) {
        if (@($rules.forbidden_capabilities) -contains $cap) { return [pscustomobject]@{ forbidden=$true; reason="forbidden capability: $cap" } }
    }
    return [pscustomobject]@{ forbidden=$false; reason='' }
}

function Sort-RouteCandidates {
    param($Candidates)
    return @($Candidates | Sort-Object @{Expression='score';Descending=$true}, @{Expression='priority';Descending=$true}, @{Expression='confidence';Descending=$true}, @{Expression='source_runtime';Descending=$false}, @{Expression='name';Descending=$false})
}

function Test-PreferredPrimary {
    param($Catalog, [string]$Intent, [string[]]$Domains, [string]$Name)
    $intentDomainMatches = @($Catalog.route_preferences.primary_by_intent_domain | Where-Object {
        [string]$_.intent -eq $Intent -and @($_.domains | Where-Object { $Domains -notcontains $_ }).Count -eq 0 -and @($_.exclude_domains | Where-Object { $Domains -contains $_ }).Count -eq 0
    })
    if ($intentDomainMatches.Count -gt 0) { return @($intentDomainMatches.skill) -contains $Name }
    $intentProperty = $Catalog.route_preferences.primary_by_intent.PSObject.Properties[$Intent]
    if ($null -ne $intentProperty) { return ([string]$intentProperty.Value -eq $Name) }
    foreach ($rule in @($Catalog.route_preferences.primary_by_intent_domain)) {
        if ([string]$rule.intent -ne $Intent -or [string]$rule.skill -ne $Name) { continue }
        $needed = @($rule.domains)
        $excluded = @($rule.exclude_domains)
        if (@($needed | Where-Object { $Domains -notcontains $_ }).Count -eq 0 -and @($excluded | Where-Object { $Domains -contains $_ }).Count -eq 0) { return $true }
    }
    foreach ($domain in @($Domains)) {
        $domainProperty = $Catalog.route_preferences.primary_by_domain.PSObject.Properties[$domain]
        if ($null -ne $domainProperty -and [string]$domainProperty.Value -eq $Name) { return $true }
    }
    return $false
}

function Get-CandidateRankings {
    param($Catalog, $Entries, [string]$Intent, [string[]]$Domains, [string]$ProfileName, [string]$Role)
    $contextKeys = Get-RouteContextKeys -Intent $Intent -Domains $Domains
    $scoring = $Catalog.candidate_scoring
    $ranked = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @($Entries | Where-Object { $_.kind -eq 'skill' })) {
        if (-not (Test-CodexSkillRuntime $entry)) { continue }
        $forbidden = Test-ProfileForbidden -Catalog $Catalog -ProfileName $ProfileName -Entry $entry -Role $Role
        if ($forbidden.forbidden) { continue }
        $roles = Get-ContextualRoles -Catalog $Catalog -Entry $entry -ContextKeys $contextKeys
        if ($roles -notcontains $Role) { continue }
        $signals = Get-EntrySignalMatches -Catalog $Catalog -Entry $entry -Domains $Domains
        $score = 0
        $components = New-Object System.Collections.Generic.List[string]
        if ($Role -eq 'primary' -and $roles -contains 'primary') { $score += [int]$scoring.contextual_primary_role; $components.Add('contextual_primary_role') }
        if ($Role -eq 'supporting' -and $roles -contains 'supporting') { $score += [int]$scoring.contextual_supporting_role; $components.Add('contextual_supporting_role') }
        if ($Role -eq 'verification' -and $roles -contains 'verification') { $score += [int]$scoring.contextual_verification_role; $components.Add('contextual_verification_role') }
        if ($signals.strong.Count -gt 0) { $score += [int]$scoring.skill_name_strong_match; $components.Add('strong_evidence') }
        if ([string]$entry.description -match '(?i)\b(use when|use this|when the user|当用户|用于)\b') { $score += [int]$scoring.description_strong_evidence; $components.Add('description_evidence') }
        if ($roles -contains $Intent) { $score += [int]$scoring.intent_match; $components.Add('intent_role_match') }
        if ([string]$entry.trigger_source -in @('frontmatter','description_use_when','when_to_use_section','trigger_section')) { $score += [int]$scoring.explicit_trigger; $components.Add('explicit_trigger') }
        if ($entry.availability.runtime_available -eq $true -and $entry.availability.stale -ne $true) { $score += [int]$scoring.fresh_runtime_available; $components.Add('fresh_runtime_available') }
        if ([double]$entry.confidence -ge 0.85) { $score += [int]$scoring.high_confidence; $components.Add('high_confidence') }
        elseif ([double]$entry.confidence -lt 0.70) { $score += [int]$scoring.low_confidence; $components.Add('low_confidence') }
        $negativeHit = $false
        foreach ($domain in @($Domains)) {
            $domainProp = $Catalog.domains.PSObject.Properties[$domain]
            if ($null -ne $domainProp) {
                foreach ($negative in @($domainProp.Value.negative_capabilities)) {
                    if (@($entry.capabilities) -contains $negative) { $negativeHit = $true }
                }
            }
        }
        if ($negativeHit) { $score += [int]$scoring.domain_conflict; $components.Add('domain_conflict') }
        if (Test-PreferredPrimary -Catalog $Catalog -Intent $Intent -Domains $Domains -Name $entry.name) {
            if ($Role -eq 'primary') { $score += [int]$scoring.preferred_primary; $components.Add('preferred_primary') }
        }
        $ranked.Add([pscustomobject][ordered]@{
            name=$entry.name
            role=$Role
            score=$score
            priority=[int]$entry.priority
            confidence=[double]$entry.confidence
            source_runtime=[string]$entry.source_runtime
            evidence=@($signals.strong + $signals.weak)
            score_components=@($components)
            availability=$entry.availability
        })
    }
    $ordered = Sort-RouteCandidates -Candidates $ranked
    $unique = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($item in $ordered) {
        if (-not $seen.ContainsKey($item.name)) { $seen[$item.name] = $true; $unique.Add($item) }
    }
    $minimum = [int]$scoring.minimum_score.$Role
    return @($unique | Where-Object { $_.score -ge $minimum })
}

function Get-ProfileCandidateSet {
    param($Catalog, $Entries, [string]$ProfileName)
    $profileProp = $Catalog.profiles.PSObject.Properties[$ProfileName]
    if ($null -eq $profileProp) { throw "Unknown profile: $ProfileName" }
    $domains = @($profileProp.Value.domains)
    $intent = if (@($profileProp.Value.intents).Count -gt 0) { [string]$profileProp.Value.intents[0] } else { 'development' }
    $primary = @(Get-CandidateRankings -Catalog $Catalog -Entries $Entries -Intent $intent -Domains $domains -ProfileName $ProfileName -Role 'primary' | Select-Object -First ([int]$profileProp.Value.max_primary))
    $supporting = @(Get-CandidateRankings -Catalog $Catalog -Entries $Entries -Intent $intent -Domains $domains -ProfileName $ProfileName -Role 'supporting' | Select-Object -First ([int]$profileProp.Value.max_supporting))
    $verification = @(Get-CandidateRankings -Catalog $Catalog -Entries $Entries -Intent $intent -Domains $domains -ProfileName $ProfileName -Role 'verification' | Select-Object -First ([int]$profileProp.Value.max_verification))
    return [pscustomobject]@{
        primary=@($primary)
        supporting=@($supporting)
        verification=@($verification)
        domains=$domains
        intent=$intent
    }
}

function Get-ProviderCandidates {
    param($Catalog, $Entries, [string[]]$Domains, [string]$ProfileName)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($property in $Catalog.provider_mappings.PSObject.Properties) {
        $mapping = $property.Value
        $domainHit = @($Domains | Where-Object { @($mapping.domains) -contains $_ }).Count -gt 0
        if (-not $domainHit) { continue }
        $providers = @($Entries | Where-Object { $_.name -eq $property.Name -and @($mapping.kinds) -contains $_.kind })
        if ($providers.Count -gt 0) {
            $provider = $providers | Sort-Object @{Expression='kind';Descending=$false}, @{Expression='source_runtime';Descending=$false} | Select-Object -First 1
            [void]$out.Add([pscustomobject]@{ name=$property.Name; kind=$provider.kind; source_runtime=$provider.source_runtime; availability=$provider.availability })
        }
    }
    return @(Get-RouteStableUnique -Items @($out | ForEach-Object { $_.name }))
}

function Test-WorkflowRouterReferenceIntegrity {
    param($Catalog, $FullIndex, $Summary, [string]$RouterPath = '')
    $rows = New-Object System.Collections.Generic.List[object]
    $entries = @($FullIndex.entries)
    function Add-ReferenceCheck {
        param([string]$Reference, [string]$ExpectedKind, [string]$Context, [bool]$AllowExternal=$false)
        $matches = @($entries | Where-Object { $_.name -eq $Reference })
        $kindMatches = @($matches | Where-Object { $_.kind -eq $ExpectedKind })
        if ($kindMatches.Count -eq 0) {
            $rows.Add([pscustomobject]@{ status='FAIL'; reference=$Reference; reason="expected kind=$ExpectedKind; context=$Context" })
            return
        }
        $entry = $kindMatches | Sort-Object @{Expression='source_runtime';Descending=$false} | Select-Object -First 1
        $discoverable = if ($ExpectedKind -eq 'skill') { $entry.availability.discoverable_by_codex } else { $null }
        $reason = "kind=$($entry.kind); runtime=$($entry.source_runtime); discoverable=$discoverable"
        if ($ExpectedKind -eq 'skill' -and $entry.availability.discoverable_by_codex -ne $true -and -not $AllowExternal) {
            $rows.Add([pscustomobject]@{ status='FAIL'; reference=$Reference; reason="skill is not Codex-discoverable; context=$Context; $reason" })
        } elseif ($ExpectedKind -eq 'skill' -and $entry.availability.discoverable_by_codex -ne $true) {
            $rows.Add([pscustomobject]@{ status='WARN'; reference=$Reference; reason="external or unknown Skill; context=$Context; $reason" })
        } else {
            $rows.Add([pscustomobject]@{ status='PASS'; reference=$Reference; reason="context=$Context; $reason" })
        }
    }
    foreach ($profileProperty in $Summary.profiles.PSObject.Properties) {
        $profile = $profileProperty.Name
        $profileValue = $profileProperty.Value
        foreach ($field in @('primary_skill_candidates','supporting_skill_candidates','verification_candidates')) {
            foreach ($name in @(ConvertTo-RouteStringArray $profileValue.$field)) { Add-ReferenceCheck -Reference $name -ExpectedKind 'skill' -Context "$profile.$field" }
        }
        foreach ($name in @(ConvertTo-RouteStringArray $profileValue.provider_candidates)) {
            $matches = @($entries | Where-Object { $_.name -eq $name -and $_.kind -in @('mcp','plugin','tool') })
            if ($matches.Count -eq 0 -and $null -ne $Catalog.provider_mappings.PSObject.Properties[$name]) { [void]$rows.Add([pscustomobject]@{ status='WARN'; reference=$name; reason="catalog-only logical provider; runtime backing is not present in Full Index; context=$profile.provider_candidates" }) }
            elseif ($matches.Count -eq 0) { [void]$rows.Add([pscustomobject]@{ status='FAIL'; reference=$name; reason="expected Provider/MCP/Plugin/Tool; context=$profile.provider_candidates" }) }
            else { [void]$rows.Add([pscustomobject]@{ status='PASS'; reference=$name; reason="provider kind=$($matches[0].kind); context=$profile.provider_candidates" }) }
        }
    }
    foreach ($property in $Catalog.route_preferences.primary_by_intent_domain) { Add-ReferenceCheck -Reference ([string]$property.skill) -ExpectedKind 'skill' -Context 'Catalog.route_preferences' }
    foreach ($property in $Catalog.route_preferences.primary_by_intent.PSObject.Properties) { Add-ReferenceCheck -Reference ([string]$property.Value) -ExpectedKind 'skill' -Context 'Catalog.route_preferences.primary_by_intent' }
    foreach ($property in $Catalog.route_preferences.primary_by_domain.PSObject.Properties) { Add-ReferenceCheck -Reference ([string]$property.Value) -ExpectedKind 'skill' -Context 'Catalog.route_preferences.primary_by_domain' }
    foreach ($property in $Catalog.skill_role_bindings.PSObject.Properties) { Add-ReferenceCheck -Reference $property.Name -ExpectedKind 'skill' -Context 'Catalog.skill_role_bindings' -AllowExternal $true }
    if (-not [string]::IsNullOrWhiteSpace($RouterPath) -and (Test-Path -LiteralPath $RouterPath -PathType Leaf)) {
        $routerText = Get-Content -Raw -LiteralPath $RouterPath
        $referenceSkills = @(Get-RouteStableUnique -Items @($entries | Where-Object kind -eq 'skill') -Property 'name')
        foreach ($entry in $referenceSkills) {
            if ($routerText -match [regex]::Escape($entry.name)) { Add-ReferenceCheck -Reference $entry.name -ExpectedKind 'skill' -Context 'WORKFLOW_ROUTER.md' -AllowExternal $true }
        }
    }
    return $rows.ToArray()
}

function Get-RouteProviders {
    param($Catalog, [string]$Prompt, [string[]]$Domains, [string[]]$ProfileProviders)
    $text = ConvertTo-RouteText $Prompt
    $tokens = Get-RouteTokens $Prompt
    $selected = New-Object System.Collections.Generic.List[string]
    foreach ($property in $Catalog.provider_preferences.explicit_terms.PSObject.Properties) {
        if (Test-RouteTerm -Text $text -Tokens $tokens -Term $property.Name -and $ProfileProviders -contains [string]$property.Value) { $selected.Add([string]$property.Value) }
    }
    foreach ($domain in @($Domains)) {
        $property = $Catalog.provider_preferences.domain_defaults.PSObject.Properties[$domain]
        if ($null -ne $property -and $ProfileProviders -contains [string]$property.Value) { $selected.Add([string]$property.Value) }
    }
    if ($selected.Count -eq 0) {
        foreach ($candidate in @($ProfileProviders | Select-Object -First 1)) { $selected.Add([string]$candidate) }
    }
    return @((Get-RouteStableUnique -Items $selected) | Select-Object -First 3)
}

function Get-RouteVerification {
    param($Catalog, [string]$Intent, [string[]]$Domains)
    $out = New-Object System.Collections.Generic.List[string]
    $intentProp = $Catalog.verification_mappings.PSObject.Properties[$Intent]
    if ($null -ne $intentProp) { foreach ($value in @($intentProp.Value)) { $out.Add([string]$value) } }
    foreach ($domain in @($Domains)) {
        $domainProp = $Catalog.verification_mappings.PSObject.Properties[$domain]
        if ($null -ne $domainProp) { foreach ($value in @($domainProp.Value)) { $out.Add([string]$value) } }
    }
    $gate = [string]$Catalog.decision_schema.mandatory_final_gate
    if (-not [string]::IsNullOrWhiteSpace($gate)) { $out.Add($gate) }
    return @(Get-RouteStableUnique -Items $out)
}

function Test-RoutePrimaryOptional {
    param($Catalog, [string]$Intent, [string[]]$Domains)
    $policy = $Catalog.route_preferences.primary_policy
    if ($null -eq $policy) { return $false }
    if (@($policy.optional_intents) -contains $Intent) { return $true }
    return @($Domains | Where-Object { @($policy.optional_domains) -contains $_ }).Count -gt 0
}

function Test-RouteHasExplicitPrimary {
    param($Catalog, [string]$Intent, [string[]]$Domains)
    $preferences = $Catalog.route_preferences
    $intentProperty = $preferences.primary_by_intent.PSObject.Properties[$Intent]
    if ($null -ne $intentProperty -and -not [string]::IsNullOrWhiteSpace([string]$intentProperty.Value)) { return $true }
    foreach ($rule in @($preferences.primary_by_intent_domain)) {
        if ([string]$rule.intent -ne $Intent) { continue }
        $needed = @($rule.domains)
        $excluded = @($rule.exclude_domains)
        if (@($needed | Where-Object { $Domains -notcontains $_ }).Count -eq 0 -and @($excluded | Where-Object { $Domains -contains $_ }).Count -eq 0) { return $true }
    }
    foreach ($domain in @($Domains)) {
        $domainProperty = $preferences.primary_by_domain.PSObject.Properties[$domain]
        if ($null -ne $domainProperty -and -not [string]::IsNullOrWhiteSpace([string]$domainProperty.Value)) {
            if ($domain -in @($Catalog.route_preferences.primary_policy.optional_domains)) { return $true }
        }
    }
    return $false
}

function Get-RouteObjectiveCount {
    param($Catalog, [string]$Text, [string[]]$Tokens)
    $rules = $Catalog.execution_gate_rules
    if ($null -eq $rules) { return 0 }
    $best = 0
    foreach ($property in $rules.objective_count_terms.PSObject.Properties) {
        $count = 0
        if (-not [int]::TryParse([string]$property.Name, [ref]$count)) { continue }
        if (@(Get-MatchedRouteTerms -Text $Text -Tokens $Tokens -Terms @($property.Value)).Count -gt 0) {
            if ($count -gt $best) { $best = $count }
        }
    }
    return $best
}

function Get-RouteExecutionGates {
    param($Catalog, [string]$Prompt, [string]$Scale, [string[]]$Domains)
    $text = ConvertTo-RouteText $Prompt
    $tokens = Get-RouteTokens $Prompt
    $rules = $Catalog.execution_gate_rules
    if ($null -eq $rules) {
        return [pscustomobject]@{
            worktree=[pscustomobject]@{ use=$false; reason='Catalog has no execution gate rules.' }
            subagents=[pscustomobject]@{ use=$false; reason='Catalog has no execution gate rules.' }
            evidence=@()
        }
    }
    $parallel = @(Get-MatchedRouteTerms -Text $text -Tokens $tokens -Terms @($rules.parallel_terms))
    $isolation = @(Get-MatchedRouteTerms -Text $text -Tokens $tokens -Terms @($rules.isolation_terms))
    $experiment = @(Get-MatchedRouteTerms -Text $text -Tokens $tokens -Terms @($rules.experiment_terms))
    $protected = @(Get-MatchedRouteTerms -Text $text -Tokens $tokens -Terms @($rules.protected_terms))
    $lowConflict = @(Get-MatchedRouteTerms -Text $text -Tokens $tokens -Terms @($rules.low_conflict_terms))
    $objectiveCount = Get-RouteObjectiveCount -Catalog $Catalog -Text $text -Tokens $tokens
    $minimumObjectives = [int]$rules.minimum_independent_objectives
    $deep = ($Scale -eq 'DEEP')
    $parallelSignal = $parallel.Count -gt 0
    $worktreeSignal = ($isolation.Count -gt 0 -or $experiment.Count -gt 0 -or $protected.Count -gt 0 -or ($parallelSignal -and $objectiveCount -ge $minimumObjectives))
    $worktreeUse = ($deep -and [bool]$rules.worktree_requires_deep -and $worktreeSignal)
    $subagentUse = ($deep -and [bool]$rules.subagent_requires_deep -and $parallelSignal -and $objectiveCount -ge $minimumObjectives -and $lowConflict.Count -gt 0)
    $workReason = if ($worktreeUse) { "DEEP task has qualifying isolation/parallel evidence; objective_count=$objectiveCount." } else { "Worktree gate not met; DEEP alone is insufficient and objective/isolation evidence is incomplete." }
    $subReason = if ($subagentUse) { "At least $minimumObjectives independent objectives, parallel benefit, and low-conflict evidence are present." } else { "Subagent gate not met; requires DEEP, parallel benefit, at least $minimumObjectives objectives, and low-conflict evidence." }
    return [pscustomobject]@{
        worktree=[pscustomobject]@{ use=[bool]$worktreeUse; reason=$workReason }
        subagents=[pscustomobject]@{ use=[bool]$subagentUse; reason=$subReason }
        evidence=@($parallel + $isolation + $experiment + $protected + $lowConflict)
        objective_count=$objectiveCount
    }
}

function Get-WorkflowRouteDecision {
    param(
        [Parameter(Mandatory=$true)][string]$Prompt,
        [Parameter(Mandatory=$true)]$Catalog,
        [Parameter(Mandatory=$true)]$Entries,
        $Summary = $null
    )
    $intentResult = Get-RouteIntent -Catalog $Catalog -Prompt $Prompt
    $domainResult = Get-RouteDomains -Catalog $Catalog -Prompt $Prompt
    $scaleResult = Get-RouteScale -Catalog $Catalog -Prompt $Prompt -Intent $intentResult.name -Domains $domainResult.domains
    $riskResult = Get-RouteRisk -Catalog $Catalog -Prompt $Prompt
    $profileResult = Get-RouteProfile -Catalog $Catalog -Domains $domainResult.domains -Intent $intentResult.name
    $gates = Get-RouteExecutionGates -Catalog $Catalog -Prompt $Prompt -Scale $scaleResult.scale -Domains $domainResult.domains
    $profile = $Catalog.profiles.PSObject.Properties[$profileResult.name].Value
    $contextDomains = @($domainResult.domains)
    $primaryRank = @(Get-CandidateRankings -Catalog $Catalog -Entries $Entries -Intent $intentResult.name -Domains $contextDomains -ProfileName $profileResult.name -Role 'primary')
    $primary = $null
    if ($intentResult.name -ne 'maintenance') {
        $primaryOptional = Test-RoutePrimaryOptional -Catalog $Catalog -Intent $intentResult.name -Domains $contextDomains
        $explicitPrimary = Test-RouteHasExplicitPrimary -Catalog $Catalog -Intent $intentResult.name -Domains $contextDomains
        if (-not $primaryOptional -or $explicitPrimary) {
            $preferred = @($primaryRank | Where-Object { Test-PreferredPrimary -Catalog $Catalog -Intent $intentResult.name -Domains $contextDomains -Name $_.name }) | Select-Object -First 1
            if ($null -ne $preferred) { $primary = [string]$preferred.name }
            elseif ($primaryRank.Count -gt 0) { $primary = [string]$primaryRank[0].name }
        }
    }
    $supportingRank = @(Get-CandidateRankings -Catalog $Catalog -Entries $Entries -Intent $intentResult.name -Domains $contextDomains -ProfileName $profileResult.name -Role 'supporting')
    $supporting = @($supportingRank | Where-Object { $_.name -ne $primary } | Select-Object -First 4 | ForEach-Object { $_.name })
    $profileProviders = @(Get-ProviderCandidates -Catalog $Catalog -Entries $Entries -Domains $contextDomains -ProfileName $profileResult.name)
    $providers = @(Get-RouteProviders -Catalog $Catalog -Prompt $Prompt -Domains $contextDomains -ProfileProviders $profileProviders)
    $verification = @(Get-RouteVerification -Catalog $Catalog -Intent $intentResult.name -Domains $contextDomains)
    $confidenceParts = @([double]$intentResult.confidence)
    if (@($domainResult.evidence).Count -gt 0) { $confidenceParts += 0.90 } else { $confidenceParts += 0.35 }
    if ($primary) { $confidenceParts += 0.90 } else { $confidenceParts += 0.65 }
    $confidence = [math]::Round((($confidenceParts | Measure-Object -Average).Average), 2)
    $rationale = [ordered]@{
        intent_matches=@($intentResult.matches)
        domain_evidence=@($domainResult.evidence)
        profile=$profileResult.name
        primary_candidates=@($primaryRank | Select-Object -First 6 name,score,priority,confidence,score_components)
        supporting_candidates=@($supportingRank | Select-Object -First 6 name,score,priority,confidence,score_components)
        runtime_filter='Only codex-discoverable, non-stale skills are eligible; Mirasim-only skills remain external.'
        minimal_capability_rule='At most one primary, at most four supporting skills, and only mapped providers.'
    }
    return [pscustomobject][ordered]@{
        router_version=[string]$Catalog.catalog_version
        intent=[string]$intentResult.name
        domains=@($domainResult.domains)
        scale=[string]$scaleResult.scale
        risk=[string]$riskResult.risk
        primary_skill=$primary
        supporting_skills=@($supporting)
        providers=@($providers)
        worktree=$gates.worktree
        subagents=$gates.subagents
        verification=@($verification)
        planning=if ($scaleResult.scale -eq 'FAST') { 'none' } elseif ($scaleResult.scale -eq 'DEEP') { 'full' } else { 'lightweight' }
        knowledge_update='none'
        confidence=$confidence
        rationale=$rationale
    }
}
