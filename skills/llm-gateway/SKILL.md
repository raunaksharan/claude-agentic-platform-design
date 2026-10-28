---
name: llm-gateway
description: This skill should be used when the user needs to design an "LLM gateway", "model gateway", "model routing", "LLM proxy", "model fallback chain", "token budget", "token quota", "prompt caching" strategy, "LLM rate limiting", "model cost tracking", "provider failover", or "data residency" for model calls. Use it whenever a system makes LLM/model API calls and needs routing, fallback, cost control, or compliance — even if the user only said "we call GPT" or "we use Claude".
---

# LLM Gateway

Design the internal gateway through which every model call flows — routing to the
right provider, falling back when one is down, enforcing token budgets, caching
prompts, tracking cost, and respecting data-residency rules. This is *not* just
"call an API with a circuit breaker" (`resilience-failure`); LLM calls have
unique properties: token-based billing, prompt caching, streaming responses,
provider-specific quota shapes, and context windows that vary by model.

## When to reach for this
The design includes one or more LLM calls, and you need to decide: which model
handles which task, what happens when a provider is down, how you prevent a
single tenant from burning your entire token budget, and whether prompts
containing PII can leave a given region. Reach here the moment someone draws
a box labeled "LLM" without specifying how calls are routed, budgeted, or
retried.

## When NOT to
A prototype calling a single model with no cost or availability concerns — just
call the API directly. Don't build a gateway until you have at least one of:
multiple models/providers, per-tenant cost isolation, data-residency
constraints, or an SLA that requires failover. Also don't put business logic
in the gateway — it routes, budgets, and retries; it doesn't decide *what* to
ask the model (that's the agent runtime → `agent-runtime`).

## Clarify first
- **Provider set** — which providers/models? (OpenAI, Anthropic, self-hosted,
  fine-tuned?) Each has different rate limits, pricing, context windows, and
  capabilities.
- **Fallback chain** — when the primary model is unavailable, what's the
  degradation path? (e.g., Claude Opus → Claude Sonnet → queue and retry.)
- **Cost model** — per-tenant budgets? Per-run caps? How are overages handled
  (hard reject vs soft alert)?
- **Streaming** — does the client need token-by-token streaming (SSE) or is
  batch response acceptable? Streaming changes the entire response path.
- **Data residency** — can all prompts go to any region, or must certain
  tenants' data stay in EU/US? This constrains provider and endpoint choice.
- **Caching opportunity** — do many runs share the same system prompt or
  context prefix? Provider-level prompt caching can cut cost and latency
  dramatically.

## The options

**Routing strategies**

- **Static routing** — each agent version maps to a fixed model. Simple,
  predictable, easy to reason about cost. Use as default.
- **Capability-based routing** — route by task type (summarization → smaller
  model, complex reasoning → larger model). Saves cost but adds routing logic.
- **Latency-based routing** — route to the provider with lowest current latency.
  Useful when multiple providers offer equivalent models.
- **Cost-optimized routing** — try cheaper model first; escalate to expensive
  model only if the cheap model's response fails a quality check. Reduces cost
  but adds latency for the retry path.

**Fallback and resilience**

- **Fallback chain** — ordered list: primary → secondary → tertiary. Circuit
  breaker per provider (→ `resilience-failure`). When primary trips, route to
  secondary. Half-open probes restore primary when it recovers.
- **Graceful degradation** — when all providers are down, the agent run moves
  to `DEGRADED` status: skip optional LLM steps, use cached responses where
  available, or park the run for retry.
- **Provider quota pooling** — aggregate rate limits across tenants; fair-share
  allocation so one tenant's burst doesn't starve others. Implement with a
  token-bucket per tenant layered under a global bucket for the provider's
  limit (→ `sharded-counters`).

**Cost control**

- **Per-tenant token budget** — monthly or daily token allocation. Tracked via
  sharded counters (→ `sharded-counters`). On budget exhaustion: reject, queue,
  or degrade to cheaper model.
- **Per-run cost cap** — dollar ceiling per agent run. The runtime tracks
  cumulative tokens × price after each LLM call; trips → end run with
  `COST_LIMIT` status.
- **Per-step token limit** — max input+output tokens for a single LLM call.
  Prevents a single step from consuming the entire run budget.

**Prompt caching**

- **Provider-level cache** — Anthropic and OpenAI support cache keys on system
  prompt prefixes. When many runs share the same system prompt (common), the
  provider serves a cache hit at reduced cost and latency.
- **Semantic dedup** — if the same semantic question was asked recently (within
  a session or across sessions), serve the cached response. Use with caution:
  only for deterministic, factual queries, never for creative or
  context-dependent responses.

**Streaming**

- **SSE (Server-Sent Events)** — token-by-token streaming from provider →
  gateway → agent runtime → client. Use when the end user sees real-time
  output. Gateway must handle partial responses, connection drops, and
  reconnect.
- **Batch response** — collect the full response before forwarding. Simpler,
  works for background agent runs where no one watches. Use as default for
  async/queued runs.

**Data residency**

- **Endpoint pinning** — route tenants in EU to EU-based model endpoints; US
  tenants to US endpoints. Requires provider support for regional endpoints.
- **Prompt classification** — classify prompt content (PII, financial data,
  health data) and enforce routing rules per classification. Prompts with
  PII → only approved regions/providers.

## Trade-offs

| Option | What it solves | What it worsens | Change it when |
|---|---|---|---|
| Static routing | Predictable, simple, auditable | No cost optimization; can't adapt to provider outages automatically | Need cost savings → capability-based routing |
| Fallback chain | Availability during provider outages | Fallback model may be lower quality; adds latency on failover | All providers equivalent → load-balance instead |
| Per-tenant token budget | Cost isolation; no runaway spend | Legitimate bursts rejected; shared-counter overhead | Tenants need burst → add burst allowance on top of budget |
| Provider-level prompt cache | Massive cost/latency reduction for shared prefixes | Cache invalidation on system prompt change; provider-specific | Prompts are all unique → no benefit |
| SSE streaming | Real-time UX; perceived latency reduction | Connection management complexity; harder to retry mid-stream | No real-time UX needed → batch is simpler |
| Regional endpoint pinning | Data residency compliance | Limits provider choice; may increase latency for some users | Single-region tenants with no compliance needs → skip |

## Behavior under stress

- **Provider outage:** Circuit breaker trips on the primary provider. Gateway
  routes all traffic to fallback. Fallback may have lower rate limits →
  per-tenant fair-share kicks in. Some runs queue. Alert fires on breaker trip
  (→ `observability`).
- **Token budget exhaustion:** A tenant's monthly budget runs out mid-day.
  Gateway rejects new LLM calls for that tenant. Agent runtime receives a
  `BUDGET_EXHAUSTED` error → run moves to `BUDGET_LIMIT` status. Tenant admin
  notified.
- **Thundering herd on provider recovery:** Primary provider comes back.
  Half-open circuit breaker admits a trickle of probes. On success, gradually
  shifts traffic back. *Don't* flip all traffic back at once — the provider
  may have a warm-up period.
- **Prompt injection in cached response:** A cached response contains injected
  instructions. Semantic dedup serves it to another run. **Mitigation:** never
  cache tool outputs or user-supplied content as reusable responses; only cache
  against system-prompt prefixes (which are controlled).

## Cross-references
- `resilience-failure` — circuit breakers, retry with jitter for provider calls
- `caching` — prompt/response caching strategies
- `sharded-counters` — per-tenant token budget counters
- `load-balancing` — distributing across provider endpoints
- `observability` — token/cost metrics, provider health dashboards
- `back-of-the-envelope` — token throughput sizing
- `agent-runtime` — every model call routes through this gateway
- `agent-security` — data classification for residency enforcement
