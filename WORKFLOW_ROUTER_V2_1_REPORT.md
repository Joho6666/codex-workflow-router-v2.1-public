# Codex Workflow Router V2.1 Reliability Report

Generated: 2026-09-13T10:34:19.4111870Z
Index snapshot generated: 2026-09-13T10:34:06.0991910Z

## A. 修改文件

- `AGENTS.md`, `WORKFLOW_ROUTER.md`, `ROUTING_CATALOG.json`
- `CAPABILITIES_FULL.json`, `CAPABILITIES_SUMMARY.json`, `CAPABILITIES.json`, `RUNTIME_TOOLS.json`, `MCP_RUNTIME_STATUS.json`
- `scripts/workflow-router-core.ps1`, `scripts/resolve-workflow-route.ps1`, `scripts/update-capability-index.ps1`, `scripts/update-mcp-runtime-status.ps1`, `scripts/test-workflow-router.ps1`, `scripts/generate-workflow-router-report.ps1`

## B. P0 Bug 修复

- Single Routing Catalog is now the machine source of truth.
- Intent and domains are separated; Worktree/Subagent are independent gates.
- Runtime filtering happens before candidate scoring; stale/unknown runtime is not treated as available.
- Profile candidates use contextual roles, score thresholds, stable sorting, and negative evidence.

## C. Intent + Domain Schema

Intents: maintenance, bugfix, refactor, development, revision, research, review, data, creative, video, automation, deployment
Domains: frontend, web, auth, backend, embedded, firmware, eda, cad, academic, document, research, creative, video, design-system, deployment, automation, orchestration, debugging

## D. Contextual Role Schema

- Roles are bound by intent/domain/capability context through `routing_roles` and Catalog bindings.
- `verification-before-completion` is verification-only; Provider entries cannot be Primary Skills.

## E. Candidate Scoring

{
  "contextual_primary_role": 100,
  "contextual_supporting_role": 60,
  "contextual_verification_role": 100,
  "skill_name_strong_match": 80,
  "description_strong_evidence": 60,
  "intent_match": 40,
  "explicit_trigger": 30,
  "fresh_runtime_available": 25,
  "high_confidence": 20,
  "low_confidence": -30,
  "weak_cross_domain_match": -60,
  "domain_conflict": -80,
  "runtime_unavailable": -100,
  "preferred_primary": 120,
  "minimum_score": {
    "primary": 120,
    "supporting": 60,
    "verification": 60
  }
}

## F. Runtime Filter

Runtime policy: {"codex_skill":{"require_kind":"skill","require_discoverable_by_codex":true,"allow_unknown_discoverability":false},"mirasim_skill":{"require_discoverable_by_codex":true,"unknown_is_external":true},"plugin":{"cached_does_not_imply_runtime_available":true},"mcp":{"configured_does_not_imply_healthy":true},"snapshot":{"stale_after_seconds":21600,"stale_runtime_is_unknown":true}}
MCP configured/visible/healthy/unknown/stale: 2 / 2 / 0 / 2 / 0

## G. Tokenizer 修复

- Compound tokens retain the original token and add split tokens for exact boundary matching.

## H. Trigger Provenance

Explicit=0; Derived=122; Fallback=162; Empty=0; ParserFailures=0

## I. Profile Before / After

Before source: `<USER_HOME>\.codex\backups\workflow-router-v2.1-p0-20260913-170103\CAPABILITIES_SUMMARY.json`
### development
- Added: 
- Removed: 
### frontend
- Added: 
- Removed: 
### backend
- Added: 
- Removed: embedded-firmware-keil
### embedded
- Added: 
- Removed: 
### eda
- Added: subagent-driven-development
- Removed: embedded-firmware-keil
### cad
- Added: 
- Removed: 
### academic
- Added: 
- Removed: 
### document
- Added: 
- Removed: 
### research
- Added: 
- Removed: 
### creative
- Added: 
- Removed: 
### video
- Added: 
- Removed: 
### deployment
- Added: 
- Removed: 
### automation
- Added: 
- Removed: 

## J. Skill Statistics

Skills=284; Classified=230; Unclassified=54; LowConfidence=54

## K. MCP Status

Configured=2; RuntimeVisible=2; Healthy=0; Unknown=2; Stale=0; SnapshotFresh=True; RuntimeFresh=True; ConfigMatch=True

## L. Runtime Snapshot

{
  "schema_version": "2.1",
  "snapshot_id": "a7400e01-9a95-4547-89f8-8f549615152f",
  "observed_at": "2026-09-13T10:32:37.7747928Z",
  "stale_after_seconds": 21600,
  "stale": false,
  "source": [
    "config.toml",
    "RUNTIME_TOOLS.json"
  ],
  "servers": [
    {
      "server": "node_repl",
      "configured": true,
      "runtime_visible": true,
      "tools_discovered": true,
      "runtime_available": null,
      "healthy": null,
      "startable": null,
      "reachable": null,
      "connected": null,
      "observed_at": "2026-09-13T10:32:37.7747928Z",
      "snapshot_id": "a7400e01-9a95-4547-89f8-8f549615152f",
      "stale": false,
      "evidence": [
        "configured from config.toml",
        "runtime tool inventory matched 3 tool(s)"
      ]
    },
    {
      "server": "chatcut_desktop",
      "configured": true,
      "runtime_visible": true,
      "tools_discovered": true,
      "runtime_available": null,
      "healthy": null,
      "startable": null,
      "reachable": null,
      "connected": null,
      "observed_at": "2026-09-13T10:32:37.7747928Z",
      "snapshot_id": "a7400e01-9a95-4547-89f8-8f549615152f",
      "stale": false,
      "evidence": [
        "configured from config.toml",
        "runtime tool inventory matched 61 tool(s)"
      ]
    }
  ]
}

## M. Router Reference Integrity

Failures=0; Checked=171
- [PASS] orchestration: context=development.primary_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] systematic-debugging: context=development.primary_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] dispatching-parallel-agents: context=development.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] embedded-debugger: context=development.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] executing-plans: context=development.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] playwright: context=development.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] planning-with-files: context=development.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] subagent-driven-development: context=development.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] embedded-firmware-keil: context=development.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] embedded-debugger: context=development.verification_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] verification-before-completion: context=development.verification_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] playwright: context=development.verification_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] browser: provider kind=plugin; context=development.provider_candidates
- [PASS] vercel: provider kind=plugin; context=development.provider_candidates
- [PASS] netlify: provider kind=plugin; context=development.provider_candidates
- [PASS] frontend-design: context=frontend.primary_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] playwright: context=frontend.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] executing-plans: context=frontend.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] dispatching-parallel-agents: context=frontend.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] subagent-driven-development: context=frontend.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] playwright: context=frontend.verification_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] verification-before-completion: context=frontend.verification_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] browser: provider kind=plugin; context=frontend.provider_candidates
- [PASS] vercel: provider kind=plugin; context=frontend.provider_candidates
- [PASS] netlify: provider kind=plugin; context=frontend.provider_candidates
- [PASS] figma: provider kind=plugin; context=frontend.provider_candidates
- [PASS] executing-plans: context=backend.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] dispatching-parallel-agents: context=backend.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] subagent-driven-development: context=backend.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] verification-before-completion: context=backend.verification_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] playwright: context=backend.verification_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] browser: provider kind=plugin; context=backend.provider_candidates
- [PASS] cloudflare: provider kind=plugin; context=backend.provider_candidates
- [PASS] supabase: provider kind=plugin; context=backend.provider_candidates
- [PASS] embedded-firmware-keil: context=embedded.primary_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] embedded-debugger: context=embedded.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] executing-plans: context=embedded.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] dispatching-parallel-agents: context=embedded.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] embedded-firmware-keil: context=embedded.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] subagent-driven-development: context=embedded.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] embedded-debugger: context=embedded.verification_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] verification-before-completion: context=embedded.verification_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] kicad: context=eda.primary_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] easyeda-agent: context=eda.primary_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] datasheets: context=eda.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] easyeda-agent: context=eda.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] executing-plans: context=eda.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] dispatching-parallel-agents: context=eda.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] bom: context=eda.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] kicad: context=eda.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] embedded-debugger: context=eda.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] subagent-driven-development: context=eda.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] verification-before-completion: context=eda.verification_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] embedded-debugger: context=eda.verification_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] solidworks-automation: context=cad.primary_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] autocad-automation: context=cad.primary_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] autocad-automation: context=cad.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] executing-plans: context=cad.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] dispatching-parallel-agents: context=cad.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] solidworks-api-skill: context=cad.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] subagent-driven-development: context=cad.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] embedded-firmware-keil: context=cad.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] verification-before-completion: context=cad.verification_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] chinese-academic-writing-cn: context=academic.primary_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] scientific-writing: context=academic.primary_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] citation-verify: context=academic.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] citation-verify: context=academic.verification_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] documents: provider kind=plugin; context=academic.provider_candidates
- [PASS] zotero: provider kind=plugin; context=academic.provider_candidates
- [PASS] chinese-academic-writing-cn: context=document.primary_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] scientific-writing: context=document.primary_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] citation-verify: context=document.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] chinese-academic-writing-cn: context=document.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] citation-verify: context=document.verification_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] documents: provider kind=plugin; context=document.provider_candidates
- [PASS] zotero: provider kind=plugin; context=document.provider_candidates
- [PASS] canva: provider kind=plugin; context=document.provider_candidates
- [PASS] chinese-academic-writing-cn: context=research.primary_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] scientific-writing: context=research.primary_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] citation-verify: context=research.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] datasheets: context=research.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] citation-verify: context=research.verification_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] documents: provider kind=plugin; context=research.provider_candidates
- [PASS] zotero: provider kind=plugin; context=research.provider_candidates
- [PASS] video-spec-builder: context=creative.primary_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] frontend-design: context=creative.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] video-shotcraft: context=creative.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] remotion-best-practices: context=creative.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] canva: provider kind=plugin; context=creative.provider_candidates
- [PASS] figma: provider kind=plugin; context=creative.provider_candidates
- [PASS] remotion: provider kind=plugin; context=creative.provider_candidates
- [PASS] video-spec-builder: context=video.primary_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] video-shotcraft: context=video.primary_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] frontend-design: context=video.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] video-shotcraft: context=video.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] remotion-best-practices: context=video.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] canva: provider kind=plugin; context=video.provider_candidates
- [PASS] figma: provider kind=plugin; context=video.provider_candidates
- [PASS] remotion: provider kind=plugin; context=video.provider_candidates
- [PASS] playwright: context=deployment.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] playwright: context=deployment.verification_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] browser: provider kind=plugin; context=deployment.provider_candidates
- [PASS] vercel: provider kind=plugin; context=deployment.provider_candidates
- [PASS] netlify: provider kind=plugin; context=deployment.provider_candidates
- [PASS] cloudflare: provider kind=plugin; context=deployment.provider_candidates
- [PASS] supabase: provider kind=plugin; context=deployment.provider_candidates
- [PASS] github: provider kind=plugin; context=deployment.provider_candidates
- [PASS] orchestration: context=automation.primary_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] orchestration: context=automation.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] dispatching-parallel-agents: context=automation.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] planning-with-files: context=automation.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] subagent-driven-development: context=automation.supporting_skill_candidates; kind=skill; runtime=codex; discoverable=True
- [PASS] systematic-debugging: context=Catalog.route_preferences; kind=skill; runtime=codex; discoverable=True
- [PASS] frontend-design: context=Catalog.route_preferences; kind=skill; runtime=codex; discoverable=True
- [PASS] embedded-firmware-keil: context=Catalog.route_preferences; kind=skill; runtime=codex; discoverable=True
- [PASS] kicad: context=Catalog.route_preferences; kind=skill; runtime=codex; discoverable=True
- [PASS] orchestration: context=Catalog.route_preferences; kind=skill; runtime=codex; discoverable=True
- [PASS] chinese-academic-writing-cn: context=Catalog.route_preferences; kind=skill; runtime=codex; discoverable=True
- [PASS] systematic-debugging: context=Catalog.route_preferences.primary_by_intent; kind=skill; runtime=codex; discoverable=True
- [PASS] chinese-academic-writing-cn: context=Catalog.route_preferences.primary_by_intent; kind=skill; runtime=codex; discoverable=True
- [PASS] video-spec-builder: context=Catalog.route_preferences.primary_by_intent; kind=skill; runtime=codex; discoverable=True
- [PASS] frontend-design: context=Catalog.route_preferences.primary_by_domain; kind=skill; runtime=codex; discoverable=True
- [PASS] embedded-firmware-keil: context=Catalog.route_preferences.primary_by_domain; kind=skill; runtime=codex; discoverable=True
- [PASS] embedded-firmware-keil: context=Catalog.route_preferences.primary_by_domain; kind=skill; runtime=codex; discoverable=True
- [PASS] kicad: context=Catalog.route_preferences.primary_by_domain; kind=skill; runtime=codex; discoverable=True
- [PASS] solidworks-automation: context=Catalog.route_preferences.primary_by_domain; kind=skill; runtime=codex; discoverable=True
- [PASS] chinese-academic-writing-cn: context=Catalog.route_preferences.primary_by_domain; kind=skill; runtime=codex; discoverable=True
- [PASS] scientific-writing: context=Catalog.route_preferences.primary_by_domain; kind=skill; runtime=codex; discoverable=True
- [PASS] orchestration: context=Catalog.route_preferences.primary_by_domain; kind=skill; runtime=codex; discoverable=True
- [PASS] video-spec-builder: context=Catalog.route_preferences.primary_by_domain; kind=skill; runtime=codex; discoverable=True
- [PASS] systematic-debugging: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [PASS] frontend-design: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [PASS] embedded-firmware-keil: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [PASS] chinese-academic-writing-cn: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [PASS] scientific-writing: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [PASS] kicad: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [PASS] easyeda-agent: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [PASS] bom: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [PASS] datasheets: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [WARN] build-keil: external or unknown Skill; context=Catalog.skill_role_bindings; kind=skill; runtime=mirasim; discoverable=
- [WARN] flash-keil: external or unknown Skill; context=Catalog.skill_role_bindings; kind=skill; runtime=mirasim; discoverable=
- [WARN] serial-monitor: external or unknown Skill; context=Catalog.skill_role_bindings; kind=skill; runtime=mirasim; discoverable=
- [PASS] embedded-debugger: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [PASS] verification-before-completion: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [WARN] static-analysis: external or unknown Skill; context=Catalog.skill_role_bindings; kind=skill; runtime=mirasim; discoverable=
- [WARN] review-bugbot: external or unknown Skill; context=Catalog.skill_role_bindings; kind=skill; runtime=mirasim; discoverable=
- [WARN] review-security: external or unknown Skill; context=Catalog.skill_role_bindings; kind=skill; runtime=mirasim; discoverable=
- [PASS] playwright: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [PASS] citation-verify: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [PASS] planning-with-files: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [PASS] executing-plans: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [PASS] dispatching-parallel-agents: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [PASS] subagent-driven-development: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [PASS] orchestration: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [PASS] solidworks-automation: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [PASS] autocad-automation: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [PASS] solidworks-api-skill: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [PASS] video-spec-builder: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [PASS] video-shotcraft: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [PASS] remotion-best-practices: context=Catalog.skill_role_bindings; kind=skill; runtime=codex; discoverable=True
- [PASS] bom: context=WORKFLOW_ROUTER.md; kind=skill; runtime=codex; discoverable=True
- [PASS] graphify: context=WORKFLOW_ROUTER.md; kind=skill; runtime=codex; discoverable=True
- [PASS] kicad: context=WORKFLOW_ROUTER.md; kind=skill; runtime=codex; discoverable=True
- [PASS] orchestration: context=WORKFLOW_ROUTER.md; kind=skill; runtime=codex; discoverable=True
- [PASS] playwright: context=WORKFLOW_ROUTER.md; kind=skill; runtime=codex; discoverable=True
- [PASS] systematic-debugging: context=WORKFLOW_ROUTER.md; kind=skill; runtime=codex; discoverable=True
- [PASS] verification-before-completion: context=WORKFLOW_ROUTER.md; kind=skill; runtime=codex; discoverable=True
- [WARN] doc: external or unknown Skill; context=WORKFLOW_ROUTER.md; kind=skill; runtime=mirasim; discoverable=
- [WARN] eval: external or unknown Skill; context=WORKFLOW_ROUTER.md; kind=skill; runtime=mirasim; discoverable=
- [WARN] review: external or unknown Skill; context=WORKFLOW_ROUTER.md; kind=skill; runtime=mirasim; discoverable=
- [WARN] workflow: external or unknown Skill; context=WORKFLOW_ROUTER.md; kind=skill; runtime=mirasim; discoverable=

## N. Profile Contamination

Count=0

## O. Static Tests

Passes=183; Failures=0; Skipped=0; Runtime=7.6.5

## P. Capability Tests

- Frontmatter literal/folded parser, trigger provenance, contextual roles, compound tokenizer, runtime filtering, and priority stability are covered by Level 2 tests.

## Q. Real Agent Eval

Status=PASS; Reason=All 8 routes satisfy the catalog rules. Selected skills have eligible Codex-runtime records; Mirasim-only build-keil, flash-keil, and serial-monitor are excluded. Single-module cases use worktree=false and subagents=false, the three independent modules use both true, and Next.js/Vercel correctly has primary_skill=null with vercel/browser providers.

## R. Routing Decisions

- maintenance / unknown / FAST / Primary= / Worktree=False / Subagents=False
- bugfix / auth,frontend / STANDARD / Primary=systematic-debugging / Worktree=False / Subagents=False
- refactor / design-system,frontend / DEEP / Primary=frontend-design / Worktree=False / Subagents=False
- development / embedded,firmware / DEEP / Primary=embedded-firmware-keil / Worktree=False / Subagents=False
- development / eda,embedded / DEEP / Primary=kicad / Worktree=False / Subagents=False
- revision / document,academic / STANDARD / Primary=chinese-academic-writing-cn / Worktree=False / Subagents=False
- development / orchestration,auth,backend / DEEP / Primary=orchestration / Worktree=True / Subagents=True
- deployment / deployment,frontend / STANDARD / Primary= / Worktree=False / Subagents=False

## S. 40+ Skill QA

SampleCount=53
- [CORRECT] kicad: runtime=codex; capabilities=eda,engineering-process,debugging,research; confidence=0.95
- [CORRECT] bom: runtime=codex; capabilities=eda,embedded,manufacturing,procurement,engineering-process; confidence=1
- [CORRECT] datasheets: runtime=codex; capabilities=eda,engineering-process,knowledge; confidence=0.95
- [CORRECT] systematic-debugging: runtime=codex; capabilities=debugging,engineering-process; confidence=1
- [CORRECT] verification-before-completion: runtime=codex; capabilities=engineering-process; confidence=1
- [CORRECT] planning-with-files: runtime=codex; capabilities=engineering-process,research; confidence=1
- [CORRECT] executing-plans: runtime=codex; capabilities=engineering-process; confidence=0.95
- [CORRECT] dispatching-parallel-agents: runtime=codex; capabilities=orchestration; confidence=0.85
- [UNKNOWN] subagent-driven-development: runtime=codex; capabilities=; confidence=0
- [CORRECT] test-driven-development: runtime=codex; capabilities=engineering-process; confidence=0.85
- [CORRECT] requesting-code-review: runtime=codex; capabilities=engineering-process; confidence=0.85
- [CORRECT] receiving-code-review: runtime=codex; capabilities=engineering-process; confidence=0.95
- [CORRECT] frontend-design: runtime=codex; capabilities=frontend,web,creative; confidence=0.95
- [CORRECT] video-shotcraft: runtime=codex; capabilities=creative,video,web; confidence=1
- [CORRECT] embedded-firmware-keil: runtime=codex; capabilities=embedded,firmware; confidence=0.95
- [ACCEPTABLE] build-keil: runtime=mirasim; capabilities=embedded,firmware; confidence=0.95
- [ACCEPTABLE] flash-keil: runtime=mirasim; capabilities=embedded,firmware,debugging; confidence=0.95
- [ACCEPTABLE] serial-monitor: runtime=mirasim; capabilities=embedded,firmware; confidence=0.95
- [CORRECT] literature-review: runtime=codex; capabilities=academic,research,engineering-process,knowledge; confidence=1
- [CORRECT] citation-management: runtime=codex; capabilities=academic,research; confidence=0.95
- [CORRECT] word-academic-docx-cn: runtime=codex; capabilities=academic,document,research; confidence=0.95
- [CORRECT] autocad-automation: runtime=codex; capabilities=cad,automation,auth,backend,engineering-process; confidence=1
- [CORRECT] solidworks-automation: runtime=codex; capabilities=automation,cad; confidence=0.95
- [ACCEPTABLE] openstoryline-use: runtime=mirasim; capabilities=video,web; confidence=0.95
- [UNKNOWN] using-superpowers: runtime=codex; capabilities=; confidence=0
- [ACCEPTABLE] token-saver-memory-dedup: runtime=mirasim; capabilities=engineering-process; confidence=0.85
- [CORRECT] sun-yuchen-perspective: runtime=codex; capabilities=research; confidence=0.85
- [ACCEPTABLE] arkcli-gen: runtime=mirasim; capabilities=backend,creative,engineering-process,video; confidence=0.85
- [UNKNOWN] gsap-plugins: runtime=codex; capabilities=; confidence=0
- [ACCEPTABLE] goal: runtime=mirasim; capabilities=; confidence=0
- [CORRECT] review-agent: runtime=codex; capabilities=engineering-process; confidence=0.85
- [ACCEPTABLE] onboard: runtime=mirasim; capabilities=; confidence=0
- [ACCEPTABLE] video-use: runtime=mirasim; capabilities=engineering-process,video; confidence=0.85
- [ACCEPTABLE] autopilot: runtime=mirasim; capabilities=; confidence=0
- [CORRECT] imagegen: runtime=codex; capabilities=creative,web; confidence=0.85
- [ACCEPTABLE] new-repo: runtime=mirasim; capabilities=engineering-process; confidence=0.85
- [ACCEPTABLE] update-cli-config: runtime=mirasim; capabilities=; confidence=0
- [UNKNOWN] gsap-utils: runtime=codex; capabilities=; confidence=0
- [CORRECT] lcsc: runtime=codex; capabilities=eda,backend,engineering-process,manufacturing,procurement; confidence=0.95
- [UNKNOWN] chatcut-visual-analysis: runtime=codex; capabilities=; confidence=0
- [CORRECT] remotion-best-practices: runtime=codex; capabilities=video,frontend,knowledge,web; confidence=0.95
- [CORRECT] solidworks-api-skill: runtime=codex; capabilities=cad,backend; confidence=1
- [CORRECT] solidworks-fillet-chamfer-cnc: runtime=codex; capabilities=cad,automation,manufacturing; confidence=0.95
- [ACCEPTABLE] arkcli-shared: runtime=mirasim; capabilities=auth,backend,debugging; confidence=0.95
- [CORRECT] pcbway: runtime=codex; capabilities=eda,manufacturing,engineering-process,procurement; confidence=0.95
- [CORRECT] codex-academic-humanizer: runtime=codex; capabilities=academic,creative; confidence=0.95
- [CORRECT] chatcut-image-gen-codex: runtime=codex; capabilities=creative; confidence=0.85
- [UNKNOWN] computer-use: runtime=codex; capabilities=; confidence=0
- [ACCEPTABLE] arkcli-code-example: runtime=mirasim; capabilities=; confidence=0
- [ACCEPTABLE] arkcli-agent: runtime=mirasim; capabilities=; confidence=0
- [ACCEPTABLE] arkcli-train-finetune: runtime=mirasim; capabilities=deployment,deployment-cloud; confidence=0.85
- [UNKNOWN] yuanbao: runtime=codex; capabilities=; confidence=0
- [ACCEPTABLE] doc: runtime=mirasim; capabilities=document; confidence=0.85

## T. Windows PowerShell Status

- PowerShell 7+: supported execution path.
- Windows PowerShell 5.1: clean `PowerShell 7+ required` exit code 64 after UTF-8 BOM handling.

## U. Remaining Issues

- Mirasim-only skills are retained in Full Index but excluded from native Codex candidate selection unless discoverability is proven.
- MCP snapshot freshness: FRESH; Runtime tools freshness: FRESH; Config parity: MATCH.
- Real Agent Eval is not accepted as passed unless an isolated Agent result is present.

## READY_FOR_ADAPTIVE_ROUTER: NO

Adaptive Router remains out of scope for this reliability release.
