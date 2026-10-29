---
name: agent-memory
description: This skill should be used when the user needs to design "agent memory", "session memory", "long-term memory" for agents, "conversation context" management, "memory retrieval", "memory write gating", "belief stability", "memory provenance", "memory decay", or "cross-session knowledge". Use it whenever an AI agent needs to remember things within a run (session context) or across runs (persistent knowledge) — even if the user only said "the agent should remember what it learned".
---

# Agent Memory

Design how an agent persists and recalls knowledge — both within a single run
(session memory: conversation context, intermediate results) and across runs
(long-term memory: facts the agent learned that are useful later). This is
*not* a cache (`caching`) or a database schema (`data-storage`); agent memory
has unique patterns: semantic retrieval, provenance tracking, confidence
gating, multi-tenant isolation, and the fundamental question of when a fact
is stable enough to commit.

## When to reach for this
The design includes an agent that accumulates knowledge during execution (e.g.,
"the user's preferred shipping address is X" or "the last deployment failed
because of Y") and that knowledge should persist beyond the current run or be
recalled within a long-running run. Reach here the moment someone says "the
agent should learn from experience" or "remember what it found last time."

## When NOT to
An agent that processes each request independently with no state between runs —
just pass the full context in the prompt each time. Don't build a memory system
until you have: runs that reference past interactions, user preferences that
must persist, or knowledge that accumulates and needs retrieval. Also don't
confuse memory with caching — a cached API response is not agent memory; it
doesn't have provenance, confidence, or decay (→ `caching`).

## Clarify first
- **Memory scope** — per-user, per-tenant, per-agent, or global? Most platforms
  need per-user within a tenant (the agent remembers things about each user it
  works with).
- **Memory lifetime** — how long should facts persist? Some are ephemeral
  (within a run), some are session-scoped (within a conversation), some are
  permanent (user preferences).
- **Retrieval method** — does the agent explicitly query memory ("what's the
  user's address?") or is memory automatically injected into context based on
  relevance?
- **Write authority** — can only the agent write memory, or can users directly
  edit/delete their stored facts?
- **Privacy and compliance** — can memory store PII? Is there a right-to-forget
  (GDPR Article 17)?

## The options

**Session memory** (within a single run)

- **Conversation context** — the full message history (user messages + model
  responses + tool results) kept in the run state. Simple, no extra infra.
  Limited by context window size.
- **Summarized context** — periodically summarize older conversation turns into
  a compressed representation. Saves context window space but loses detail.
  Use when runs have many steps (>20).
- **Structured scratchpad** — the agent maintains a structured state object
  (key-value pairs, a task list, accumulated findings) alongside the
  conversation. Explicit, auditable, survives checkpoints
  (→ `agent-runtime`).

**Long-term memory** (across runs)

- **Fact store** — key-value or document store of facts, each with metadata:
  `fact_id`, `content`, `source_run_id`, `source_step_no`, `created_at`,
  `confidence`, `last_verified`, `tenant_id`, `user_id`.
- **Vector store** — embed facts as vectors for semantic retrieval. When the
  agent needs to recall relevant facts, embed the current context and retrieve
  nearest neighbors. Works well for open-ended recall ("what do I know about
  this customer?"). Use with a keyword filter for precision
  (→ `distributed-search`).
- **Knowledge graph** — facts as nodes, relationships as edges. Better for
  structured relationships ("Alice manages Bob, who owns Project X"). Higher
  implementation cost; use only when relationships matter.

**Memory retrieval**

- **Explicit query** — the agent decides when to query memory (a tool call:
  `recall_memory(query)`). Gives the agent control but requires it to know
  when to look.
- **Auto-injection** — before each model call, automatically retrieve the top-k
  most relevant memories for the current context and inject them into the
  prompt. No agent decision needed, but adds latency and may inject irrelevant
  memories.
- **Hybrid** — auto-inject high-confidence, high-relevance memories; let the
  agent explicitly query for everything else. Best of both worlds.

**Memory write gating** (when is a fact stable enough to commit?)

- **Immediate write** — every fact the agent encounters is written immediately.
  Simple but noisy; the memory fills with transient, uncertain information.
- **Confidence threshold** — only write facts above a confidence score. The
  confidence comes from: explicit user confirmation, multiple corroborating
  sources, or a verification step.
- **End-of-run commit** — accumulate candidate facts during the run; at the
  end, a quality pass filters and commits only stable facts. Reduces noise
  but loses facts from crashed runs.
- **Quarantine** — write facts immediately but mark as `UNVERIFIED`. Only
  `VERIFIED` facts are auto-injected. A background process or a future run
  verifies quarantined facts.

**Memory decay and maintenance**

- **TTL-based** — facts expire after a configurable TTL unless refreshed.
  Good for facts that go stale (prices, availability, status).
- **Verification trigger** — flag facts for re-verification after N days or
  after a contradicting fact arrives.
- **Staleness detection** — track `last_verified` timestamp. On retrieval,
  flag facts that haven't been verified recently.
- **Right to forget** — user-initiated deletion of all their memories. Must
  cascade to derived facts and any cached representations
  (→ `data-storage` for cascade design).

## Trade-offs

| Option | What it solves | What it worsens | Change it when |
|---|---|---|---|
| Full conversation context | Simple; no loss of detail | Context window limit; cost per call grows | Runs have >20 steps → summarize or use scratchpad |
| Summarized context | Fits long conversations in context window | Lossy; may drop important details | Critical details lost → structured scratchpad |
| Fact store (KV) | Simple, fast, explicit | No semantic retrieval; must know the exact key | Need open-ended recall → add vector store |
| Vector store | Semantic retrieval; "what do I know about X?" | Embedding cost; retrieval quality depends on embedding model | Relationships matter → add knowledge graph |
| Auto-injection | Agent doesn't need to decide when to recall | Latency; irrelevant memories pollute context | Irrelevant memories degrade quality → explicit query |
| Immediate write | No facts lost | Noisy; transient info persists | Too much noise → confidence threshold or quarantine |
| Quarantine | Low noise; verified facts only | Useful facts delayed; verification overhead | Verification too slow → lower threshold |
| TTL-based decay | Stale facts auto-cleaned | Legitimate permanent facts expire | Mix of ephemeral and permanent → per-fact TTL |

## Behavior under stress

- **Memory store overload:** Many concurrent runs writing facts. Write-back
  queue buffers writes; reads served from cache (→ `caching`). If queue
  backs up, degrade to session-memory-only (skip long-term writes).
- **Retrieval latency spike:** Vector search slow under load. Auto-injection
  timeout → skip memory injection for this step. Agent runs without memory
  context (degraded but functional). Alert fires (→ `observability`).
- **Contradicting facts:** Agent retrieves two facts that contradict each
  other (old: "user prefers email," new: "user prefers Slack"). Resolution:
  prefer the most recent, highest-confidence fact. Flag the conflict in the
  agent's context so it can ask the user if needed.
- **GDPR deletion request:** User invokes right-to-forget. All facts scoped
  to `user_id` are deleted from the fact store AND the vector store (vector
  deletion can be slow — use a soft-delete + background purge). Cached
  representations are invalidated. Audit log records the deletion request.

## Cross-references
- `data-storage` — memory store (Postgres for facts, DynamoDB for session state)
- `distributed-search` — vector + keyword hybrid search for memory retrieval
- `caching` — hot memory items cached for fast retrieval
- `blob-store` — large memory objects (documents, images)
- `agent-runtime` — session memory lives in run state; read/write during steps
- `agent-security` — memory isolation (tenant A can't access tenant B's memory)
- `observability` — memory retrieval latency, write queue depth metrics
