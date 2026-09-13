# Codex Workflow Router v2.1

This is the human-readable constitution for the global Router. The machine-readable rules live only in `<USER_HOME>\.codex\ROUTING_CATALOG.json`. Generator, resolver, Self-Test, and report scripts must consume that Catalog instead of maintaining private routing tables.

## Execution chain

```text
Prompt
→ Intent + Domains
→ Scale + Risk
→ Routing Catalog
→ Runtime Filter
→ Candidate Scoring
→ Minimal Capability Set
→ Execute
→ Verify
→ Real Agent Eval
```

The overall lifecycle remains:

```text
Task → Context → Classify → Route → Execute → Verify → Persist
```

## Routing contract

Every non-trivial route is represented by one decision object:

```json
{
  "router_version": "2.1.0",
  "intent": "bugfix",
  "domains": ["frontend", "auth"],
  "scale": "STANDARD",
  "risk": "HIGH",
  "primary_skill": "systematic-debugging",
  "supporting_skills": [],
  "providers": ["browser"],
  "worktree": { "use": false, "reason": "..." },
  "subagents": { "use": false, "reason": "..." },
  "verification": ["browser-console", "build", "verification-before-completion"],
  "planning": "lightweight",
  "knowledge_update": "none",
  "confidence": 0.95,
  "rationale": {}
}
```

`task_type` is legacy terminology only. New routing uses one `intent` plus zero or more `domains`. A task may have multiple domains, such as `frontend + auth` or `embedded + eda`.

The Minimal Sufficient Capability law is mandatory:

- At most one `PRIMARY SKILL`; simple edits may use `primary_skill: null`.
- Zero to four `SUPPORTING SKILLS`.
- Providers are tools, MCPs, or Plugins and are selected only by required capability, never merely because they are installed.
- A name in `supporting_skills` or `verification` must not be copied into `providers` unless the Full Index also contains that name as `kind=mcp`, `kind=plugin`, or `kind=tool`; for example, `playwright` is a Skill and is not a Provider by itself.
- Verification is one logical strategy assembled from the Catalog; `verification-before-completion` is a final gate only and can never be an implementation Primary.
- Skills, Providers, Plugins, MCPs, Hooks, and Automations not selected by the route are not loaded.

## Classification

The Router first reads the prompt and relevant project context, then resolves:

- `intent`: `maintenance`, `bugfix`, `refactor`, `development`, `revision`, `research`, `review`, `data`, `creative`, `video`, `automation`, or `deployment`.
- `domains`: for example `frontend`, `backend`, `auth`, `embedded`, `firmware`, `eda`, `cad`, `academic`, `document`, `video`, `deployment`, or `orchestration`.
- `scale`: `FAST`, `STANDARD`, or `DEEP`.
- `risk`: `LOW`, `MEDIUM`, `HIGH`, or `CRITICAL`.

The exact terms, precedence, score weights, negative evidence, profile limits, and compatibility mapping are defined in the Catalog. Strong evidence wins over weak keywords. Unknown evidence stays unknown instead of receiving a decorative label.

## Contextual roles and runtime truth

Roles are contextual, not global:

- `PRIMARY`: the one skill that determines the main execution paradigm.
- `SUPPORTING`: focused domain or process assistance.
- `VERIFICATION`: checks, gates, review, and evidence collection.
- `TOOL/PROVIDER`: MCP, Plugin, or runtime tool used only when capability is required.

The same skill can have different roles in different domains. For example, KiCad can be Primary for EDA, Supporting for an EDA-adjacent embedded task, and never an automatic Primary for ordinary software backend work.

Runtime states are independent facts:

- Codex Skill eligibility requires `kind=skill`, `source_runtime=codex`, and `discoverable_by_codex=true`.
- Mirasim-only Skills remain external capabilities unless Codex discoverability is explicitly proven.
- Plugin `cached=true` does not imply `runtime_available`, `connected`, or `healthy`.
- MCP `configured=true` does not imply runtime visibility, discovered tools, reachability, or health.
- A stale runtime snapshot is unknown for current routing.

## Scale, Worktree, and Subagent gates

- `FAST`: isolated typo, README, small configuration or single-file edit. No heavy planning, Worktree, Subagent, or broad capability loading.
- `STANDARD`: ordinary feature, bugfix, document, or multi-file change. Use lightweight planning and targeted verification.
- `DEEP`: large or cross-module work, complex engineering, research, or independently parallelizable work. Use full planning and evaluate isolation and delegation explicitly.

`DEEP` does not imply Worktree. Worktree is considered only for isolation value, risk isolation, parallel implementation, experiment comparison, workspace conflict, or protected long-running work. The decision must include `worktree.use` and a reason.

`DEEP` does not imply Subagents. Subagents require at least two genuinely independent objectives, low file ownership conflict, and parallel benefit greater than integration cost. The decision must include `subagents.use` and a reason.

## Progressive context loading

Load context in this order, stopping when sufficient:

```text
AGENTS.md
→ project structure
→ README
→ docs/INDEX.md
→ PROJECT_STATE.md
→ ARCHITECTURE.md
→ DECISIONS.md
→ task-relevant source files
```

FAST does not read an entire project. STANDARD reads the relevant module and necessary documentation. DEEP may load architecture, decisions, project state, and cross-module dependencies. Do not read every Skill or write temporary logs to Obsidian.

## Verification

Verification is selected from the Catalog by intent and domain:

- Code: tests, lint, typecheck, build, and runtime checks as applicable.
- Frontend: build, browser flow, console, interaction, and responsive checks.
- Embedded: compile, link, authorized flash, serial/log, and hardware state.
- EDA: connectivity, BOM, DRC, and output-file checks.
- CAD: feature tree, dimensions, exports, and artifact checks.
- Academic/Research: source quality, facts, citations, completeness, and delivery format.
- Document: content, rendering, pagination, and file integrity.
- Deployment: build, deployment status, health checks, and authentication/data boundaries.
- Review: diff, risk, test, and security checks.

No completion claim is valid without fresh evidence. Report `SKIPPED`, `NOT_TESTED`, or `UNAVAILABLE` when a verification boundary remains.

## Knowledge persistence

Do not write temporary commands, transient errors, or ordinary tool output to Obsidian. Persist only meaningful project state changes, durable decisions, knowledge-structure changes, reusable methods, stable workflows, or lessons learned. Preserve the existing rule that only Graphify output is maintained; never modify user-authored source notes.

## Debugging the Router

When the user asks `Explain routing decision`, explicitly print a `ROUTING_DECISION` JSON block and the evidence for intent, domains, scale, risk, contextual roles, runtime filtering, candidate scores, providers, Worktree, Subagents, and Verification. This is explanatory behavior, not an invented slash command.

The resolver is `<USER_HOME>\.codex\scripts\resolve-workflow-route.ps1`. The capability generator is `<USER_HOME>\.codex\scripts\update-capability-index.ps1`. The deterministic contract suite is `<USER_HOME>\.codex\scripts\test-workflow-router.ps1`. A real Agent Eval is reported separately and must never be simulated by the deterministic suite.

