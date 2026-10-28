# Generalizing the 21 System-Design Skills for Any AI Agent Architecture

## 1. Executive Summary

The existing 21 building-block skills cover general distributed-systems design well — storage, caching, messaging, observability, resilience, etc. But they were written for *request-response systems* (feeds, chat apps, URL shorteners). AI agent architectures introduce patterns that don't map cleanly onto any current skill:

- **Long-running, stateful execution** (not a request that completes in milliseconds)
- **LLM calls as a first-class infrastructure concern** (not just "call a downstream API")
- **Tool use with authorization and schema enforcement** (not just "service A calls service B")
- **Human-in-the-loop approval flows** (not just async processing)
- **Agent memory** (not just a cache or a database)
- **Multi-agent coordination** (not just service decomposition)
- **Eval-gated deployment** (not just canary on latency/error rate)

This doc proposes **7 new skills** and **5 skill extensions** to close the gap, then shows how all 28 skills (21 existing + 7 new) connect when designing any agent platform.

---

## 2. Current Skills: What They Already Cover for Agents

These existing skills apply directly to agent architectures with no changes needed:

| Skill | Agent Architecture Application |
|---|---|
| **requirements-scoping** | Pinning down agent capabilities, autonomy level, tenant model, compliance constraints |
| **back-of-the-envelope** | Runs/day, concurrent runs, LLM token throughput, checkpoint storage, trace volume |
| **api-design** | The Run API contract (`POST /v1/runs`, status polling, approval endpoints) |
| **data-storage** | Run state (DynamoDB/Aurora), tool registry (Postgres), tenant config (Postgres+RLS) |
| **blob-store** | Checkpoint blobs, large tool outputs, model artifacts |
| **caching** | Tool response caching, prompt caching, tenant config caching |
| **messaging-streaming** | Run queue, event-driven agent invocation, step completion events |
| **distributed-logging** | Agent trace/log aggregation pipeline |
| **distributed-search** | Tool catalog search (BM25 + kNN hybrid), trace search |
| **dns** | Regional agent endpoint routing |
| **load-balancing** | Distributing run requests across runtime worker pools |
| **consistency-coordination** | Run state leases, checkpoint consistency, approval ordering |
| **resilience-failure** | Circuit breakers on LLM/tool calls, retry with jitter, rate limiting |
| **sequencer** | Run IDs, step IDs, trace IDs (time-sortable for replay) |
| **sharded-counters** | Per-tenant token usage counters, rate-limit tallies |
| **task-scheduling** | Scheduled/recurring agent runs, delayed retries, cron-triggered agents |
| **observability** | SLOs for agent runs (success rate, p95 latency, cost), alerting on quality regression |
| **scaling-evolution** | Growth path from single-tenant to multi-tenant to multi-region agent platform |
| **content-delivery** | Edge caching of agent UI assets (less central but still applies) |
| **service-decomposition** | Splitting agent platform into runtime, gateway, registry, control plane |

**Key insight:** these skills provide the *infrastructure layer*. What's missing is the *agent-specific layer* that sits on top.

---

## 3. Gap Analysis: What's Missing

### Gap 1: Agent Runtime & Durable Execution
**What it is:** The execution engine that runs an agent's step loop — model call → tool call → model call — with durability guarantees. A run can last seconds or days (waiting for approval). If a pod dies mid-step, another worker must resume from the last checkpoint.

**Why no current skill covers it:**
- `task-scheduling` covers job queues and worker leasing, but not the *internal execution model* of a single long-running task (graph vs loop, checkpointing, step budgets, cancellation).
- `messaging-streaming` covers the queue transport, but not durable state machines.
- `consistency-coordination` covers leases and consistency, but not the agent-specific patterns (step replay, idempotent tool calls, waiting-is-free).

**Not covered anywhere:**
- Graph execution vs bounded tool loop (LangGraph-style typed state vs simple model→tool loop)
- Checkpoint-per-step with lease+heartbeat
- At-least-once steps requiring idempotency keys per step
- Step/token/cost budgets and loop-safety (max steps, repeated-call detection)
- Park-and-resume for approval waits (no pod held)
- Cancellation between steps + in-flight abort
- Build-vs-buy: Temporal/Step Functions vs home-grown queue+state

### Gap 2: LLM Gateway
**What it is:** A dedicated gateway for all model calls — routing, fallback, token quotas, prompt caching, deadline enforcement, and cost tracking. This is *not* just "call a downstream API with a circuit breaker."

**Why no current skill covers it:**
- `resilience-failure` covers circuit breakers, retries, and rate limiting generically, but LLM calls have unique concerns: token-based billing, prompt caching, model fallback chains, streaming responses, data residency for prompts, and provider-specific quota shapes.
- `api-design` covers client-facing contracts, not internal model-routing layers.

**Not covered anywhere:**
- Model routing: primary → fallback → smaller model degradation chain
- Per-tenant and per-run token budgets (not just rate limits — cost caps)
- Prompt caching strategies (provider-level cache, semantic dedup)
- Deadline propagation (a run's wall-clock deadline flows into the LLM call timeout)
- Streaming vs batch response handling
- Data residency: which prompts can leave which region
- Provider quota pooling and fair-share across tenants

### Gap 3: Tool Registry & Gateway
**What it is:** A versioned catalog of tools an agent can call, plus a gateway that validates, authorizes, and executes every tool call.

**Why no current skill covers it:**
- `api-design` covers the *external* API contract, not an internal tool catalog.
- `service-decomposition` covers how services find each other, but tool registries have agent-specific concerns: versioned schemas, side-effect classification (READ/WRITE), required-scopes, data classification, and per-tool rate limits.

**Not covered anywhere:**
- Tool as a versioned contract: JSON schema in/out, side_effect flag, required_scopes, timeout, rate limit, data classification
- Agent versions pin `tool@version` (breaking changes = new major version)
- Gateway responsibilities: schema validation of model's arguments, scope checking, OBO (on-behalf-of) execution, field projection (redact fields the user can't see), audit logging
- Tool selection at scale: when hundreds of tools exist, retrieve top-k by hybrid search rather than stuffing all schemas into the prompt
- Sandboxed code-execution tools (gVisor/Firecracker, no egress)

### Gap 4: Human-in-the-Loop & Approvals
**What it is:** The pattern where an agent proposes an action (especially WRITE side-effects), parks the run, and waits for a human to approve or reject before executing.

**Why no current skill covers it:**
- `messaging-streaming` covers async hand-offs but not structured approval flows.
- No skill addresses the unique challenge of *re-authorization at execution time* (permissions may have changed between proposal and approval).

**Not covered anywhere:**
- Approval policies (per tenant, per tool, per side-effect class)
- Park-and-resume: persist proposed action, release the pod, resume on approval
- Re-authorization on resume (check scopes again at execution time)
- Approval timeout/TTL and escalation
- Batch approval (approve multiple proposed actions at once)
- Audit trail: who approved what, when, with what context

### Gap 5: Agent Memory
**What it is:** How an agent remembers things across steps within a run (session memory) and across runs (long-term memory).

**Why no current skill covers it:**
- `caching` covers hot-data caching, but agent memory is *knowledge the agent accumulates*, not a cache of database reads.
- `data-storage` covers schema design, but agent memory has unique patterns: per-user scoping, provenance tracking, belief stability gating, and retrieval-based recall.

**Not covered anywhere:**
- Session memory (within a run): conversation context, intermediate results, accumulated state
- Long-term memory: per-tenant, per-user, with provenance and confidence
- Memory retrieval: semantic search over accumulated facts
- Memory write gating: when is a fact stable enough to commit to long-term memory
- Memory decay/TTL: facts that expire or need re-verification
- Memory isolation: tenant A's agent can't access tenant B's memory

### Gap 6: Agent Security & Authorization
**What it is:** The security model specific to agents — how tool calls respect user permissions, how prompt injection is defended against, and how agent actions are scoped.

**Why no current skill covers it:**
- `resilience-failure` covers rate limiting but not authorization.
- No skill addresses OBO (on-behalf-of) execution, where the agent acts with the *user's* permissions rather than a god-mode service account.

**Not covered anywhere:**
- On-behalf-of (OBO) execution: the agent calls tools with the invoking user's scopes, not its own
- Prompt injection defense: tool outputs and retrieved docs are untrusted data; the model can't widen its own scope
- No god-mode service account: authorization lives in the gateway, not in the agent
- Scope narrowing: agent can do less than the user, never more
- Audit: every tool call logged with who (user), what (tool+args), when, and the agent version

### Gap 7: Eval & Safe Agent Deployment
**What it is:** How to test and deploy a new agent version safely — golden-set evaluation, trajectory testing, and canary rollout with agent-specific metrics.

**Why no current skill covers it:**
- `scaling-evolution` covers growth paths, but not eval-gated deployment.
- `observability` covers SLOs and alerting, but not agent-specific quality metrics (task success rate, trajectory correctness, escalation rate).

**Not covered anywhere:**
- Golden tasks with expected outcome AND expected trajectory (right tools, right order)
- Permission test cases (correct answer: "I can't do that")
- Prompt injection test cases
- LLM judge from a different model family, calibrated against human labels
- Canary rollout with agent-specific metrics: task success rate, escalation rate, tool error rate, cost per run
- Version pinning in run state: in-flight runs finish on the version they started
- Auto-rollback on quality regression (not just latency/error rate)

---

## 4. Proposed Changes

### 4A. New Skills (7)

#### NEW: `agent-runtime`
**Covers:** Durable execution for agent step loops.
**Core topics:**
- Execution models: graph/workflow (typed state, nodes, conditional edges) vs bounded tool loop (model→tool→model with step budget)
- Checkpoint-per-step: after every side-effecting step, persist state keyed `(run_id, step_no)`
- Lease+heartbeat: a worker holds a lease; if the pod dies, lease expires and another worker resumes from last checkpoint
- At-least-once steps → every tool call carries idempotency key `run_id:step_no`
- Loop safety: max-steps cap, repeated-identical-tool-call detection, per-run cost cap → `NEEDS_REVIEW` on trip
- Park-and-resume: waiting (for approvals, slow tools) is free — state persisted, no pod held
- Cancellation: checked between steps; in-flight calls aborted
- Build vs buy: Temporal/Step Functions vs queue+leases+checkpoints

**Connections to other skills:**
- Uses → `messaging-streaming` (run queue), `data-storage` (run state store), `blob-store` (checkpoint blobs), `consistency-coordination` (leases), `sequencer` (run/step IDs)
- Feeds → `observability` (one trace per run), `agent-eval-deploy` (version pinning)
- Invoked by → `task-scheduling` (scheduled runs), `api-design` (Run API)

#### NEW: `llm-gateway`
**Covers:** Infrastructure for all model calls.
**Core topics:**
- Model routing: primary → fallback → degraded model chain, per-agent-version or per-tenant
- Token budgets: per-tenant, per-run, per-step token caps (not just rate limits — cost caps)
- Deadline propagation: run's wall-clock deadline → LLM call timeout
- Prompt caching: provider-level cache keys, semantic dedup of repeated context
- Streaming: SSE/chunked response handling for real-time UX
- Data residency: which prompts can be sent to which provider/region
- Provider quota pooling: fair-share across tenants when a provider rate-limits
- Retry + jitter + circuit breaker (extends `resilience-failure` for LLM-specific shapes)
- Cost tracking: tokens in/out per call, mapped to provider pricing

**Connections to other skills:**
- Uses → `resilience-failure` (breakers, retries), `caching` (prompt/response caching), `load-balancing` (distributing across provider endpoints)
- Feeds → `observability` (token/cost metrics), `back-of-the-envelope` (token throughput sizing)
- Called by → `agent-runtime` (every model call routes through this)

#### NEW: `tool-registry-gateway`
**Covers:** Versioned tool catalog and the enforcement gateway.
**Core topics:**
- Tool as a versioned contract: JSON schema (input/output), `side_effect` (READ/WRITE), `required_scopes`, timeout, rate limit, data classification, owner
- Agent version pins `tool@version`; breaking changes = new major version
- Gateway path: schema validate model's arguments → check tenant has tool enabled → check user scopes → call OBO → project out restricted fields → write audit record
- Tool selection at scale: hybrid search (BM25 + kNN, RRF) over catalog, filtered by tenant's enabled tools
- Sandboxed execution: code-execution tools in gVisor/Firecracker, default-deny egress
- MCP/A2A integration: external tool protocols, allow-listing
- WRITE tools: require approval per tenant policy, re-authorize at execution time

**Connections to other skills:**
- Uses → `distributed-search` (tool catalog search), `api-design` (tool schema design), `data-storage` (registry in Postgres), `resilience-failure` (per-tool breakers/rate limits), `caching` (tool response caching)
- Feeds → `agent-security` (authorization enforcement), `observability` (tool call metrics)
- Called by → `agent-runtime` (every tool call routes through this)

#### NEW: `human-in-the-loop`
**Covers:** Approval and review flows within agent execution.
**Core topics:**
- Approval triggers: per tenant policy, per tool, per side-effect class (WRITE always, READ sometimes)
- Park-and-resume: serialize proposed action → persist → release pod → notify user → resume on decision
- Re-authorization on resume: scopes may have changed; re-check before executing
- Approval timeout: TTL on pending approvals, escalation policy, auto-reject
- Batch approval: approve/reject multiple proposed actions
- Approval UX: surface tool name, arguments, and context to the approver
- Audit: decision, approver identity, timestamp, context shown

**Connections to other skills:**
- Uses → `agent-runtime` (park/resume), `messaging-streaming` (notification delivery), `data-storage` (approval records), `api-design` (approval endpoints)
- Feeds → `observability` (approval backlog age, decision latency), `agent-security` (re-authorization)

#### NEW: `agent-memory`
**Covers:** How agents persist and recall knowledge.
**Core topics:**
- Session memory: conversation context and intermediate results within a single run (stored in run state)
- Long-term memory: per-tenant, per-user facts that persist across runs
- Memory retrieval: semantic search (embedding + keyword) over accumulated facts
- Memory write gating: confidence threshold, evidence stability, quarantine for unstable beliefs
- Memory provenance: which run, which tool call, which user interaction produced this fact
- Memory decay: TTL, re-verification triggers, staleness detection
- Memory isolation: tenant-scoped, user-scoped, never cross-tenant

**Connections to other skills:**
- Uses → `data-storage` (memory store), `distributed-search` (semantic retrieval over memories), `blob-store` (large memory objects), `caching` (hot memory items)
- Called by → `agent-runtime` (read/write memory during step execution)

#### NEW: `agent-security`
**Covers:** Authorization, scope enforcement, and prompt injection defense for agents.
**Core topics:**
- On-behalf-of (OBO) execution: agent acts with the invoking user's scopes, never its own service account
- Scope narrowing: agent ≤ user; agent can do less, never more
- Prompt injection defense: tool outputs and retrieved docs are untrusted data → model can't widen scope because authorization is in the gateway, not the model
- Data classification: tool inputs/outputs tagged by sensitivity; redact before prompt injection
- Field projection: strip fields the user can't see before they enter the model's context
- No god-mode: every tool call goes through the gateway, which checks authorization at call time
- MCP/external tool allow-listing: only approved external tools, with scope restrictions

**Connections to other skills:**
- Uses → `tool-registry-gateway` (enforcement point), `api-design` (auth in API contracts), `consistency-coordination` (strong consistency for permission checks)
- Feeds → `observability` (auth failures, scope violations), `human-in-the-loop` (re-authorization on resume)

#### NEW: `agent-eval-deploy`
**Covers:** Testing and safely rolling out agent versions.
**Core topics:**
- Golden tasks: input → expected outcome AND expected trajectory (right tools, right arguments, right order)
- Permission tests: cases where the correct answer is "I can't do that"
- Injection tests: attempts to widen scope via prompt injection
- LLM judge: a different model family scores outputs, calibrated against human labels
- CI gate: block deployment if golden-set regression exceeds threshold
- Canary rollout: route x% of a tenant cohort to new version; compare task success rate, escalation rate, tool error rate, p95 latency, cost per run
- Version pinning: in-flight runs finish on the version they started
- Auto-rollback: deployment-pointer flip on quality regression
- K8s integration: rolling update with PDB, graceful shutdown (SIGTERM → checkpoint → release lease)
- Eval load isolation: separate provider quota for CI, so evals can't starve production

**Connections to other skills:**
- Uses → `observability` (canary metrics), `agent-runtime` (version pinning in run state), `messaging-streaming` (routing by version)
- Feeds → `scaling-evolution` (deployment as a scaling concern)

---

### 4B. Existing Skill Extensions (5)

#### EXTEND: `service-decomposition`
**Add a section:** "Agent platform decomposition"
- Standard agent platform components: Run API, runtime workers, tool gateway, LLM gateway, control plane, registry, approval service
- Each component's scaling profile and why it's a separate service
- API gateway / BFF patterns for agent UX (SSE for streaming, webhook for async completion)

#### EXTEND: `resilience-failure`
**Add a section:** "LLM and tool failure patterns"
- Provider outage cascading: when the primary model is down, fallback chain behavior
- Token quota exhaustion: graceful degradation vs queuing
- Tool timeout handling: tool calls can be much slower than typical API calls (minutes for some tools)
- Thundering herd on provider recovery: ramp-up after a circuit breaker opens

#### EXTEND: `observability`
**Add a section:** "Agent-specific observability"
- One trace per run: spans for run → step → llm_call / tool_call
- Agent-specific SLIs: task success rate, trajectory correctness, escalation rate, cost per run
- Trace attributes: tenant_id, agent@version, model, prompt_version, tokens, cost, tool@version, outcome
- Run replay: checkpoints + spans reconstruct exactly what the model saw and did
- PII redaction: raw prompts to a restricted short-retention store

#### EXTEND: `data-storage`
**Add a section:** "Agent state storage patterns"
- Run state: `PK tenant_id#run_id, SK step_no` — status, lease_owner, lease_expiry, checkpoint ref, idempotency key
- Why DynamoDB/key-value fits run state (conditional writes for leases, TTL for cleanup) while Postgres fits registry/config (relational queries, joins, RLS)
- Polyglot persistence for agents: KV for run state, relational for registry, object store for checkpoints, search for traces

#### EXTEND: `back-of-the-envelope`
**Add a section:** "Agent capacity algebra"
- Input variables: tenants, runs/day, steps/run, tokens/step, concurrent runs
- Key derivations: LLM calls/s, tool calls/s, checkpoint writes/s, trace docs/s
- Example: 10K tenants × 100 runs/day = 1M runs/day → at 7 steps/run → 7M steps/day → ~80 steps/s average, ~800/s peak
- Little's law for LLM gateway: concurrent_calls = arrival_rate × avg_duration
- Storage: run state retention, trace retention, checkpoint retention

---

## 5. How the 28 Skills Connect: Reference Architecture

Below is how the skills compose when designing an agent platform. Each node is a component; the label in `[brackets]` is the primary skill that designs it. Arrows show data/control flow.

```
                                    ┌─────────────────────────────┐
                                    │  Requirements & Capacity    │
                                    │  [requirements-scoping]     │
                                    │  [back-of-the-envelope]     │
                                    └─────────────┬───────────────┘
                                                  │ drives all sizing
                                                  ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────────────────┐
│ Client / UI  │───▶│ DNS          │───▶│ Load Balancer / Gateway  │
│              │    │ [dns]        │    │ [load-balancing]         │
│              │    └──────────────┘    │ [service-decomposition]  │
│              │                        │ AuthN, rate limit,       │
│              │◀── SSE/webhook ───────│ idempotency              │
└──────────────┘                        └───────────┬──────────────┘
                                                    │
                              ┌──────────────────────┼──────────────────────┐
                              │                      │                      │
                              ▼                      ▼                      ▼
                    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
                    │ Run API         │    │ Control Plane   │    │ Event Bus       │
                    │ [api-design]    │    │ Agent versions, │    │ Business events │
                    │ POST /v1/runs   │    │ deployments,    │    │ trigger runs    │
                    │ GET status      │    │ tenant config   │    │ [messaging-     │
                    │ POST approval   │    │ [data-storage]  │    │  streaming]     │
                    └────────┬────────┘    └────────┬────────┘    └────────┬────────┘
                             │                      │                      │
                             ▼                      │                      │
                    ┌─────────────────┐              │                      │
                    │ Run Queue       │◀─────────────┘──────────────────────┘
                    │ Per-tenant      │   version resolution
                    │ fair share      │
                    │ [messaging-     │
                    │  streaming]     │
                    │ [task-scheduling│
                    │  for scheduled] │
                    └────────┬────────┘
                             │ dequeue + lease
                             ▼
              ┌──────────────────────────────┐
              │     Agent Runtime Workers    │
              │     [agent-runtime] ◀── NEW  │
              │                              │
              │  ┌────────────────────────┐  │
              │  │ Step Loop:             │  │
              │  │ model call → tool call │  │
              │  │ → checkpoint → repeat  │  │
              │  │                        │  │
              │  │ • Graph or bounded loop│  │
              │  │ • Lease + heartbeat    │  │
              │  │ • Step/token/cost cap  │  │
              │  │ • Cancel between steps │  │
              │  └────────────────────────┘  │
              │                              │
              │  Stateless pods on K8s       │
              │  [scaling-evolution]          │
              └──┬────┬────┬────┬────┬───────┘
                 │    │    │    │    │
       ┌─────────┘    │    │    │    └──────────┐
       ▼              │    │    │               ▼
┌──────────────┐      │    │    │     ┌──────────────────┐
│ Run State    │      │    │    │     │ OTel Collector    │
│ DynamoDB/    │      │    │    │     │ [observability]   │
│ Aurora +     │      │    │    │     │ [distributed-     │
│ S3 blobs     │      │    │    │     │  logging]         │
│ [data-storage│      │    │    │     └───────┬──────────┘
│  agent-      │      │    │    │             │
│  runtime]    │      │    │    │      ┌──────┴──────┐
│ [blob-store] │      │    │    │      ▼             ▼
│ [consistency-│      │    │    │  ┌────────┐  ┌──────────┐
│  coordination│      │    │    │  │Elastic │  │Prometheus│
│  for leases] │      │    │    │  │search  │  │ metrics  │
└──────────────┘      │    │    │  │traces/ │  └──────────┘
                      │    │    │  │logs    │
                      │    │    │  │[dist-  │
                      │    │    │  │search] │
                      │    │    │  └────────┘
                      │    │    │
                      ▼    │    ▼
           ┌──────────┐    │    ┌──────────────────────┐
           │LLM       │    │    │ Tool Gateway          │
           │Gateway   │    │    │ [tool-registry-       │
           │[llm-     │    │    │  gateway] ◀── NEW     │
           │ gateway] │    │    │                        │
           │ ◀── NEW  │    │    │ Schema validate →     │
           │          │    │    │ scope check →          │
           │ Primary →│    │    │ OBO execute →          │
           │ fallback │    │    │ field project →        │
           │ → degrade│    │    │ audit log              │
           │          │    │    │                        │
           │ Token    │    │    │ [agent-security] ◀─NEW │
           │ budgets, │    │    │ [resilience-failure]   │
           │ streaming│    │    │ [caching]              │
           │ residency│    │    └──┬─────────┬───────────┘
           │          │    │       │         │
           │[resilience│   │       ▼         ▼
           │-failure]  │   │  ┌────────┐ ┌────────────┐
           │[caching]  │   │  │Tool    │ │Workday/    │
           └─────┬─────┘   │  │Registry│ │External    │
                 │         │  │Postgres│ │APIs, MCP   │
                 ▼         │  │[data-  │ │tools,      │
           ┌──────────┐    │  │storage]│ │sandboxed   │
           │ Model    │    │  └────────┘ │code tools  │
           │ Providers│    │             └────────────┘
           │ (OpenAI, │    │
           │  Anthropic│   │
           │  etc.)   │    │
           └──────────┘    │
                           ▼
                ┌──────────────────────┐
                │ Approval Service     │
                │ [human-in-the-loop]  │
                │ ◀── NEW              │
                │                      │
                │ WRITE proposed →     │
                │ park run →           │
                │ notify user →        │
                │ on decision: resume  │
                │ + re-authorize       │
                │                      │
                │ [agent-security]     │
                └──────────────────────┘

    ┌──────────────────────────────────────┐
    │ Cross-cutting concerns               │
    │                                      │
    │ • Agent Memory [agent-memory] ◀─ NEW │
    │   Session: in run state              │
    │   Long-term: per-tenant/user store   │
    │   Retrieval: semantic search         │
    │                                      │
    │ • Eval & Deploy                      │
    │   [agent-eval-deploy] ◀── NEW        │
    │   Golden sets, trajectory tests,     │
    │   canary rollout, auto-rollback      │
    │                                      │
    │ • Tenant Isolation                   │
    │   [service-decomposition] extended   │
    │   Pooled vs dedicated runtime,       │
    │   per-tenant KMS, crypto-shredding   │
    │                                      │
    │ • IDs everywhere                     │
    │   [sequencer] run_id, step_id,       │
    │   trace_id, tool_call_id             │
    │                                      │
    │ • Audit Log (WORM)                   │
    │   [data-storage]                     │
    │   who, agent@version, tool@version,  │
    │   args hash, outcome                 │
    └──────────────────────────────────────┘
```

---

## 6. Walk-Through: How to Design Any Agent Platform Using These Skills

**Step 1 — Requirements** `[requirements-scoping]`
What does the agent do? What can it NOT do? What's the tenant model? What's the autonomy level? What must be approved by a human?

**Step 2 — Capacity** `[back-of-the-envelope]` (extended)
Tenants × runs/day × steps/run × tokens/step → derive LLM calls/s, tool calls/s, checkpoint writes/s, trace volume, storage.

**Step 3 — API contract** `[api-design]`
Run API: create run, poll status, submit approval. Tool registry API: register tool, list tools, deprecate version.

**Step 4 — Data model** `[data-storage]` (extended)
Run state (KV), registry + config (relational + RLS), checkpoints (object store), traces (search engine), audit (WORM append-only).

**Step 5 — High-level design** `[service-decomposition]` (extended)
Split into: API gateway, Run API, run queue, runtime workers, LLM gateway, tool gateway, control plane, approval service, OTel pipeline. Each component sized by step 2.

**Step 6 — Deep dives** (pick by risk)
- Agent runtime + durable execution `[agent-runtime]`
- LLM gateway `[llm-gateway]`
- Tool registry + gateway `[tool-registry-gateway]`
- Authorization model `[agent-security]`
- Human-in-the-loop `[human-in-the-loop]`
- Agent memory `[agent-memory]`
- Eval-gated deploys `[agent-eval-deploy]`
- Multi-tenant isolation `[service-decomposition]` + `[consistency-coordination]`
- Observability + run replay `[observability]` + `[distributed-logging]` + `[distributed-search]`

**Step 7 — Capacity sizing** `[back-of-the-envelope]` + `[scaling-evolution]`
Size each component from step 5. Identify what's CP (leases, approvals, audit) vs AP (search, dashboards).

**Step 8 — Bottlenecks & trade-offs** `[scaling-evolution]` + `[resilience-failure]`
First to break at 10×. Trade-off pairs: graph vs free loop, durable-execution engine vs home-grown, pooled vs dedicated, all-tools-in-prompt vs top-k retrieval.

---

## 7. Applicability Beyond Workday

These 7 new skills aren't Workday-specific. They apply to any agent platform:

| Pattern | Example platforms |
|---|---|
| Agent runtime + durable execution | LangGraph Cloud, CrewAI, AutoGen, any custom agent runner |
| LLM gateway | LiteLLM, Portkey, any model routing layer |
| Tool registry + gateway | MCP servers, OpenAI function calling, any tool-use agent |
| Human-in-the-loop | Any agent that takes real-world actions (CRM updates, code commits, financial transactions) |
| Agent memory | Mem0, Zep, LangMem, any agent needing cross-session knowledge |
| Agent security | Any multi-tenant agent platform, any agent acting on behalf of users |
| Eval & safe deploy | Any production agent system (not just SaaS) |

The existing 21 skills remain unchanged for non-agent designs. The 7 new skills activate only when the system being designed involves agents.

---

## 8. Summary: Full Skill Inventory (28 skills)

### Infrastructure Layer (21 existing — unchanged)
1. requirements-scoping
2. back-of-the-envelope *(extended with agent capacity algebra)*
3. api-design
4. data-storage *(extended with agent state patterns)*
5. blob-store
6. caching
7. consistency-coordination
8. content-delivery
9. distributed-logging
10. distributed-search
11. dns
12. load-balancing
13. messaging-streaming
14. observability *(extended with agent-specific SLIs)*
15. resilience-failure *(extended with LLM/tool failure patterns)*
16. scaling-evolution
17. sequencer
18. service-decomposition *(extended with agent platform decomposition)*
19. sharded-counters
20. task-scheduling
21. architecture-diagram

### Agent Layer (7 new)
22. **agent-runtime** — durable execution, step loops, checkpointing, lease+heartbeat
23. **llm-gateway** — model routing, token budgets, fallback, streaming, residency
24. **tool-registry-gateway** — versioned tool catalog, schema validation, OBO execution
25. **human-in-the-loop** — approval flows, park/resume, re-authorization
26. **agent-memory** — session + long-term memory, retrieval, write gating
27. **agent-security** — OBO, scope enforcement, prompt injection defense
28. **agent-eval-deploy** — golden sets, trajectory testing, canary, auto-rollback
