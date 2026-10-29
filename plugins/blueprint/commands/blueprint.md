---
description: Run the bottom-up system-design workflow on a problem — clarify, estimate, design with building blocks, weigh trade-offs, stress-test, and diagram. Covers both infrastructure and AI agent platform architecture. Great for design questions and system-design interview practice.
argument-hint: <system to design, e.g. "a URL shortener", "WhatsApp at 1B users", or "a multi-tenant AI agent platform">
allowed-tools:
- "Task"
- "Skill"
- "Read"
- "Write"
- "Glob"
- "Grep"
- "Bash"
---

Run the system-design process for: **$ARGUMENTS**

Drive this as a collaborative design session using the plugin's 28 building-block skills (21 infrastructure + 7 agent-platform), following the GUIDE reasoning loop. Do not jump to a finished architecture.

1. **Launch the orchestrator.** Use the Task tool to run the `system-design-orchestrator` agent on the problem above. It loads the `system-design` skill (the method) and composes the building-block skills — including agent-platform skills when the problem involves AI agents, LLMs, or autonomous systems.
   - If subagent launch is unavailable, run the loop inline yourself: invoke the `system-design` skill first, then route to building-block skills as each concern arises — invoke each skill, don't paraphrase it.

2. **Building-block catalog:**
   - **Infrastructure (21):** `requirements-scoping`, `back-of-the-envelope`, `api-design`, `data-storage`, `caching`, `load-balancing`, `messaging-streaming`, `consistency-coordination`, `resilience-failure`, `content-delivery`, `scaling-evolution`, `service-decomposition`, `dns`, `sequencer`, `blob-store`, `observability`, `distributed-logging`, `distributed-search`, `task-scheduling`, `sharded-counters`, `architecture-diagram`.
   - **Agent platform (7):** `agent-runtime`, `llm-gateway`, `tool-registry-gateway`, `human-in-the-loop`, `agent-memory`, `agent-security`, `agent-eval-deploy`.
   - Five infrastructure skills have **agent platform extension** sections: `back-of-the-envelope`, `data-storage`, `observability`, `resilience-failure`, `service-decomposition`.

3. **For agent platform designs**, always address: durable execution model (`agent-runtime`), LLM cost controls (`llm-gateway`), tool authorization (`agent-security`), and eval/deploy pipeline (`agent-eval-deploy`).
