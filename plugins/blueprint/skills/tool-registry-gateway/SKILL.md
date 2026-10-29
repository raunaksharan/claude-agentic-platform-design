---
name: tool-registry-gateway
description: This skill should be used when the user needs to design a "tool registry", "tool catalog", "tool gateway", "function calling" infrastructure, "MCP server" registry, "tool versioning", "tool schema validation", "tool authorization", "on-behalf-of" (OBO) tool execution, "tool selection" or "tool retrieval" at scale, or "sandboxed code execution" for agents. Use it whenever an AI agent calls external tools/functions and you need to manage which tools exist, how they're versioned, how calls are validated and authorized, and how tools are selected from a large catalog — even if the user only said "the agent uses tools".
---

# Tool Registry & Gateway

Design the versioned catalog of tools an agent can call, plus the gateway that
validates, authorizes, and executes every tool call. In an agent platform, the
model proposes a tool call (function name + arguments); the gateway is the
enforcement layer between the model's intent and the actual execution. Without
it, the model calls whatever it wants with whatever arguments it invents, and
you have no audit trail, no authorization, and no way to safely evolve tool
contracts.

## When to reach for this
The design includes an AI agent that calls tools (APIs, code execution, data
lookups), and you need to decide: how tools are registered and versioned, how
the model's proposed arguments are validated against a schema, who authorizes
the call, and how you select the right tools from a large catalog. Reach here
the moment someone says "the agent calls our APIs" without explaining how those
APIs are managed, versioned, or secured.

## When NOT to
An agent with 2–3 hardcoded tools that never change — just validate inline and
call directly. Don't build a registry until you have: tools that evolve
independently, multiple agent versions that need different tool versions,
multi-tenant access control on tools, or a catalog large enough that stuffing
all schemas into the prompt is impractical (→ `back-of-the-envelope` for
context window math).

## Clarify first
- **Tool count** — how many tools today, and how many in a year? This drives
  whether all schemas fit in the prompt or you need retrieval-based selection.
- **Side effects** — which tools are READ (safe to retry, no approval needed)
  vs WRITE (may need approval, must be idempotent)? This drives approval
  policy (→ `human-in-the-loop`).
- **Authorization model** — does the agent call tools with its own service
  account (god-mode, dangerous) or with the invoking user's scopes (OBO)?
  (→ `agent-security`).
- **Versioning cadence** — how often do tool schemas change? Do multiple agent
  versions coexist in production? This drives version pinning strategy.
- **External tools** — does the agent call third-party tools (MCP servers,
  partner APIs)? These need allow-listing, sandboxing, and separate
  rate limits.

## The options

**Registry data model**

- **Tool contract:** Each tool is a versioned record:
  - `tool_id`, `version` (semver), `status` (active/deprecated/disabled)
  - `input_schema` (JSON Schema for the model's arguments)
  - `output_schema` (JSON Schema for the response)
  - `side_effect` enum: `READ` | `WRITE` | `ADMIN`
  - `required_scopes` (OAuth scopes the invoking user must hold)
  - `timeout_ms`, `rate_limit` (per-tenant calls/min)
  - `data_classification` (PII, financial, health — drives field projection)
  - `owner` (team that maintains the tool)
- **Agent version pins `tool@version`** — an agent version declares which tools
  it uses and at which versions. A breaking schema change = new major version.
  In-flight runs keep using the version they started with.
- **Storage:** Postgres with RLS per tenant (→ `data-storage`). Small, relational,
  needs joins (agent_version → tool_version → schema).

**Gateway execution path** (every tool call traverses this pipeline)

1. **Schema validation** — validate the model's proposed arguments against the
   tool's `input_schema`. Reject malformed calls before execution. This catches
   hallucinated parameters.
2. **Tenant check** — is this tool enabled for the calling tenant? Some tools
   are tenant-specific or premium-tier.
3. **Scope check** — does the invoking user hold the `required_scopes`? Enforced
   here, not in the agent code (→ `agent-security`).
4. **Rate limit check** — has this tenant exceeded the tool's per-tenant rate
   limit? (→ `sharded-counters`).
5. **OBO execution** — call the underlying API with the user's delegated
   credentials, not a service account. The gateway holds a short-lived OBO
   token scoped to the user's permissions.
6. **Field projection** — strip response fields the user's role can't see
   (e.g., salary fields for a non-HR user). Applied before the response enters
   the model's context window.
7. **Audit log** — write a WORM record: `run_id`, `step_no`, `tool@version`,
   `arguments_hash`, `user_id`, `tenant_id`, `outcome`, `latency_ms`.

**Tool selection at scale**

- **All-in-prompt** — stuff all tool schemas into the system prompt. Works for
  <20 tools. Simple, no retrieval infra.
- **Retrieval-based (top-k)** — hybrid search (BM25 + kNN, RRF fusion) over
  the tool catalog, filtered by tenant's enabled tools. Return top-k most
  relevant tool schemas for the current user message. Works for hundreds of
  tools (→ `distributed-search`).
- **Two-stage** — coarse retrieval (top-20) → model re-ranks to top-5 → only
  those schemas enter the prompt. Balances recall and context window cost.

**Sandboxed execution** (for code-execution tools)

- Run user-submitted or model-generated code in a sandboxed environment:
  gVisor, Firecracker microVM, or a container with default-deny egress.
- Resource limits: CPU time, memory, network (no egress by default).
- Input/output size limits to prevent context window overflow.

## Trade-offs

| Option | What it solves | What it worsens | Change it when |
|---|---|---|---|
| All-in-prompt | Simple; model sees all tools | Context window bloat; cost per call; irrelevant tools confuse model | >20 tools → retrieval |
| Retrieval-based top-k | Scales to hundreds of tools; focused context | Retrieval misses (model doesn't know a tool exists); infra cost | Recall issues → add two-stage re-ranking |
| OBO execution | Least-privilege; user-scoped access | Token management complexity; refresh/expiry handling | Single-tenant, trusted agent → service account OK |
| Schema validation at gateway | Catches hallucinated params; clean errors | Latency per call; schema maintenance burden | Schemas change hourly → too much friction; validate loosely |
| Version pinning | Safe co-existence of agent versions | Old agent versions accumulate; deprecation management | Aggressive deprecation policy → force-upgrade old agents |
| Sandboxed code execution | Safe model-generated code | Higher latency; sandbox escape risk; resource overhead | Code is pre-approved (not model-generated) → skip sandbox |

## Behavior under stress

- **Schema validation failures spike:** The model is hallucinating tool
  arguments (common after a model update or prompt change). Gateway rejects the
  calls. Agent runtime detects repeated failures → escalates to `NEEDS_REVIEW`.
  **Mitigation:** include example arguments in tool descriptions; pin model
  version per agent version.
- **Tool rate limit exhaustion:** One tenant's agent calls a tool too
  aggressively. Rate limiter rejects excess calls. Agent runtime receives
  `RATE_LIMITED` → backs off with jitter. **Mitigation:** per-tenant, per-tool
  rate limits in the registry; circuit breaker on the tool if it's also slow
  (→ `resilience-failure`).
- **External tool (MCP server) unavailable:** Third-party MCP server is down.
  Gateway circuit breaker trips. Agent runtime treats it as a tool failure →
  falls back to alternative tool or parks for manual intervention.
- **OBO token expired mid-run:** A long-running agent's OBO token expires
  between steps. Gateway attempts refresh. If refresh fails (user revoked
  access), run moves to `AUTH_FAILED` status.

## Cross-references
- `api-design` — tool schema design (input/output contracts)
- `data-storage` — registry in Postgres with RLS
- `distributed-search` — hybrid search for tool catalog retrieval
- `resilience-failure` — per-tool circuit breakers and rate limits
- `caching` — tool response caching (for READ tools)
- `sharded-counters` — per-tenant, per-tool rate limit counters
- `agent-security` — OBO authorization, scope enforcement
- `agent-runtime` — every tool call routes through this gateway
- `human-in-the-loop` — WRITE tools may trigger approval flow
- `observability` — tool call metrics (latency, error rate, per-tool)
