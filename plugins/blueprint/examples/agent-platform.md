# Example: AI Agent Platform

## Prompt

```
/design an AI agent platform where agents can book meetings, query databases,
and send emails — with human approval for anything over $1000
```

## What happens

The orchestrator detects agent-platform concerns and routes to both infrastructure and agent skills:

1. **Clarify** — Multi-tenant? How many agents? Concurrent executions? SLAs?
2. **Estimate** — Agent executions/sec, LLM token throughput, tool call volume
3. **Propose** — Architecture with durable execution, tool registry, approval flows
4. **Evaluate** — Temporal vs custom step-loop, centralized vs per-agent LLM gateway
5. **Stress-test** — Agent stuck in retry loop, LLM provider outage, approval timeout
6. **Iterate** — "Add audit logging for compliance" → `agent-security` + `observability`

## Skills invoked

- `agent-runtime` — durable execution, checkpointing
- `llm-gateway` — model routing, rate limiting, fallback
- `tool-registry-gateway` — tool discovery, OBO authorization
- `human-in-the-loop` — approval flows for high-value actions
- `agent-security` — tenant isolation, prompt injection defense
- `agent-memory` — conversation state, context windows
- `data-storage` — execution logs, agent state
- `messaging-streaming` — async tool results, event bus
- `observability` — agent traces, LLM latency dashboards
