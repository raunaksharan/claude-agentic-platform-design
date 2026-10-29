# Claude Agentic Platform Design Skills

A plugin of **28 system-design skills** for designing AI agent platforms — from infrastructure primitives to agent-specific building blocks.

## What's inside

### 21 infrastructure building-block skills (from the system-design-skills plugin)
General-purpose system design skills that apply to any distributed system:

`api-design` · `architecture-diagram` · `back-of-the-envelope` · `blob-store` · `caching` · `consistency-coordination` · `content-delivery` · `data-storage` · `distributed-logging` · `distributed-search` · `dns` · `load-balancing` · `messaging-streaming` · `observability` · `requirements-scoping` · `resilience-failure` · `scaling-evolution` · `sequencer` · `service-decomposition` · `sharded-counters` · `task-scheduling`

Five of these have been **extended with agent-platform sections**: `back-of-the-envelope`, `data-storage`, `observability`, `resilience-failure`, `service-decomposition`.

### 7 new agent-layer skills
Purpose-built for AI agent architectures:

| Skill | Covers |
|---|---|
| `agent-runtime` | Durable execution, step loop, checkpoint, lease + heartbeat, park/resume, cancellation |
| `llm-gateway` | Model routing, fallback chains, per-tenant token budgets, cost caps, prompt caching, streaming |
| `tool-registry-gateway` | Tool as versioned contract, 7-step gateway pipeline, tool selection at scale, sandboxed execution |
| `human-in-the-loop` | Approval trigger policies, park/resume flow, approval UX, timeout + escalation, batch approval |
| `agent-memory` | Session memory, long-term memory (fact store, vector store, knowledge graph), retrieval, decay |
| `agent-security` | OBO authorization (RFC 8693), scope enforcement, prompt injection defense, WORM audit trail |
| `agent-eval-deploy` | Golden task sets, LLM judge, CI eval gates, canary rollout, version management, auto-rollback |

### Orchestrator
`system-design` — drives the GUIDE reasoning loop (clarify → estimate → propose → evaluate trade-offs → stress-test → iterate) and composes the building-block skills.

## Skill format

Each skill follows a consistent structure:
- **YAML frontmatter** — `name` and `description` with trigger phrases
- **Intro paragraph** — what the skill covers and why it matters
- **When to reach for this / When NOT to** — scope boundaries
- **Clarify first** — questions to answer before designing
- **The options** — patterns and their use cases
- **Trade-offs table** — solves / worsens / change-it-when for each option
- **Behavior under stress** — what breaks and how to mitigate
- **Cross-references** — links to related skills

## Architecture overview

```
┌─────────────────────────────────────────────────┐
│                   Clients                        │
└──────────────────────┬──────────────────────────┘
                       ▼
┌──────────────────────────────────────────────────┐
│              API Gateway / BFF                    │
│         (auth, routing, rate-limit)               │
└──────────────────────┬───────────────────────────┘
                       ▼
┌──────────────────────────────────────────────────┐
│              Agent Runtime                        │
│  ┌─────────┐  ┌────────────┐  ┌──────────────┐  │
│  │Step Loop│→ │Checkpoint  │  │Park / Resume │  │
│  │         │  │Store       │  │(approval)    │  │
│  └────┬────┘  └────────────┘  └──────────────┘  │
│       │                                          │
│       ▼                                          │
│  ┌─────────────────────────────────────────┐     │
│  │  Per-step: model_call OR tool_call      │     │
│  └────┬──────────────────┬─────────────────┘     │
└───────┼──────────────────┼───────────────────────┘
        ▼                  ▼
┌──────────────┐  ┌──────────────────┐
│ LLM Gateway  │  │ Tool Gateway     │
│ - routing    │  │ - schema validate│
│ - fallback   │  │ - OBO auth       │
│ - quotas     │  │ - audit          │
└──────────────┘  └──────────────────┘
        │                  │
        ▼                  ▼
┌──────────────┐  ┌──────────────────┐
│ Model APIs   │  │ Tool backends    │
│ (Claude,     │  │ (HRIS, Calendar, │
│  GPT, etc.)  │  │  Email, etc.)    │
└──────────────┘  └──────────────────┘

Cross-cutting:
  Agent Memory ←→ Agent Runtime (context injection)
  Agent Security ←→ Tool Gateway (OBO auth, scope enforcement)
  Observability ←→ Everything (metrics, traces, alerts)
  Eval & Deploy ←→ Agent Runtime (canary, version management)
```

## Design doc

See `docs/design-doc.md` for the full analysis: gap identification, architecture walkthrough, and rationale for each new skill.

## Usage

These skills are designed to be used as a Claude plugin. Each skill's `description` field contains trigger phrases that activate it in context.
