---
name: agent-runtime
description: This skill should be used when the user needs to design an "agent runtime", "agent execution engine", "durable execution" for agents, "step loop", "checkpoint" or "checkpointing" for agent runs, "agent orchestration", "lease and heartbeat" for long-running agent tasks, "agent cancellation", "loop safety" or "step budget", "park and resume" for agent execution, or choosing between a "workflow graph vs tool loop" execution model. Use it whenever an AI agent must survive crashes mid-task, resume from a checkpoint, enforce cost/step caps, or wait for external input without holding compute — even if the user only said "make the agent reliable".
---

# Agent Runtime & Durable Execution

Design the execution engine that runs an agent's step loop — model call → tool
call → model call — with durability guarantees. A run can last seconds (a simple
lookup) or days (waiting for human approval on a financial transfer). If a pod
dies mid-step, another worker must resume from the last checkpoint, not start
over. Get this wrong and you lose work, double-execute side effects, or hold
expensive compute idle while waiting for a human.

## When to reach for this
The design includes an AI agent that calls tools, and you need to decide how it
executes: what happens when it crashes, how it waits for slow dependencies or
approvals, how you cap runaway loops, and whether execution follows a
pre-defined graph or a free-form model-driven loop. Reach here the moment
someone says "the agent runs tasks" without explaining what keeps a half-done
task alive.

## When NOT to
Before the agent's capabilities and tool set are defined — the execution model
depends on whether tools have side effects, whether approvals are needed, and
how many steps a typical run takes (→ `requirements-scoping`). Don't pick a
workflow engine because it sounds robust; a simple queue + lease + checkpoint
is enough for most single-agent platforms, and Temporal/Step Functions add
operational cost you may not need yet (→ `scaling-evolution`).

## Clarify first
- **Execution model** — does the agent follow a pre-defined graph (typed state,
  conditional edges, parallel branches) or a bounded tool loop (model picks the
  next tool, capped at N steps)? This is the biggest architectural fork.
- **Step duration** — are steps milliseconds (a DB lookup) or minutes (a complex
  tool call, a code execution sandbox)? Drives timeout and heartbeat design.
- **Side effects** — do tools write to external systems? If yes, every step needs
  an idempotency key so a resumed run doesn't double-execute (→ `api-design`).
- **Wait patterns** — does the agent ever wait for external input (human approval,
  a long-running tool, a scheduled delay)? If yes, it must park without holding
  a pod (→ `human-in-the-loop`).
- **Cost and safety caps** — what's the max steps, max tokens, max cost per run?
  What happens when a cap trips — fail, pause for review, or degrade?

## The options

**Execution model** (pick one; most platforms start with a bounded loop)

- **Bounded tool loop** — the model picks the next tool each step; a step counter
  and cost cap enforce termination. Simple, flexible, works for most use cases.
  The agent is "just a while loop with a model call."
- **Workflow graph (DAG)** — a pre-defined graph of typed nodes with conditional
  edges and parallel branches. Deterministic, auditable, supports complex
  multi-agent handoffs. More upfront design, less runtime flexibility. Examples:
  LangGraph, AWS Step Functions, Temporal workflows.
- **Hybrid** — a graph of stages where some stages contain a bounded tool loop.
  Common in production: the graph handles the macro flow (intake → process →
  review → complete) while loops handle the micro decisions within a stage.

**Durability** (layered; most designs combine all three)

- **Checkpoint per step** — after every side-effecting step, persist state keyed
  `(run_id, step_no)` to a durable store. On crash recovery, resume from the
  last checkpoint. Non-negotiable for any agent with tool side effects.
- **Lease + heartbeat** — a worker holds a time-limited lease on a run; if the
  pod dies, the lease expires and another worker picks up the run. Heartbeats
  extend the lease while the worker is alive. Prevents zombie runs and
  split-brain execution.
- **Idempotency keys per step** — every tool call carries
  `run_id:step_no` as an idempotency key. The tool gateway deduplicates
  replayed calls. Without this, checkpoint-resume doubles side effects.

**Loop safety** (enforce all of these)

- **Step cap** — hard limit on steps per run. Trips → `NEEDS_REVIEW` status.
- **Token cap** — cumulative input+output tokens across all LLM calls in the run.
- **Cost cap** — dollar-denominated ceiling per run (tokens × price).
- **Repeated-call detection** — if the model makes the same tool call with the
  same arguments N times in a row, break the loop and escalate.
- **Wall-clock deadline** — maximum elapsed time for a run (excluding parked
  wait time). Propagates into LLM call timeouts (→ `llm-gateway`).

**Park and resume** (for waits that shouldn't hold compute)

- Serialize the proposed action and full conversation state → persist to run
  state → release the pod → set status to `WAITING`. On approval/completion,
  enqueue a resume event → a worker picks up the run, loads state, continues.
- The key insight: **waiting is free** — no pod, no cost. The run is just a row
  in a database until it's resumed.

**Build vs buy**

- **Home-grown (queue + lease + checkpoint)** — a message queue
  (`messaging-streaming`), a run-state table with conditional writes for leases
  (`data-storage`, `consistency-coordination`), and S3 for checkpoint blobs
  (`blob-store`). Full control, minimal dependencies, sufficient for most
  single-agent platforms.
- **Durable execution engine (Temporal, Step Functions, Durable Functions)** —
  built-in retry, timeout, saga, and workflow versioning. Worth the operational
  cost when you have complex multi-step workflows with compensation logic, or
  when you need workflow versioning (running old and new workflow definitions
  simultaneously).

## Trade-offs

| Option | What it solves | What it worsens | Change it when |
|---|---|---|---|
| Bounded tool loop | Simple, flexible, model-driven | No static analysis of flow; harder to audit/replay | Need deterministic multi-agent handoffs → graph |
| Workflow graph | Deterministic, auditable, parallel branches | Upfront design cost; less flexible for open-ended tasks | Simple single-agent tasks don't need graph overhead |
| Checkpoint per step | Crash recovery without re-execution | Write amplification; checkpoint storage cost | Steps are pure/read-only → skip checkpoint for those |
| Lease + heartbeat | Prevents zombie runs and split-brain | Lease tuning (too short → false takeover; too long → stuck) | Tune lease to 3× heartbeat interval |
| Park and resume | Free waiting; no idle compute | State serialization complexity; resume latency | Waits are always <1s → just hold the pod |
| Home-grown | Full control, minimal deps | You own the retry/timeout/saga logic | Complex compensation flows → Temporal/Step Functions |
| Temporal/Step Functions | Built-in durability, versioning, sagas | Operational cost, vendor lock-in, learning curve | Simple queue+lease is enough → don't add Temporal |

## Behavior under stress

- **Pod crash mid-step:** Lease expires after TTL. Another worker dequeues the
  run, loads the last checkpoint, replays from `step_no + 1`. The tool gateway
  deduplicates the replayed call via idempotency key. **Risk:** if the
  checkpoint write itself failed, the step re-executes — tool idempotency is
  the safety net.
- **Runaway loop:** Model keeps calling the same tool or oscillating between two
  tools. Step cap trips → status moves to `NEEDS_REVIEW`. An alert fires
  (→ `observability`). A human reviews and either resumes with adjusted
  instructions or cancels.
- **Thundering herd on queue:** Many runs enqueued at once (batch trigger,
  scheduled jobs). Workers autoscale, but LLM gateway rate-limits downstream
  (→ `llm-gateway`). Backpressure: queue depth metric → autoscaler →
  LLM concurrency limit. Runs wait in queue rather than overwhelming the model
  provider.
- **Approval timeout:** A parked run waits for approval that never comes.
  TTL on the approval record → status moves to `TIMED_OUT`. Escalation policy
  notifies the approver's manager or auto-rejects
  (→ `human-in-the-loop`).

## Cross-references
- `messaging-streaming` — run queue transport
- `data-storage` — run state store (DynamoDB/Aurora)
- `blob-store` — checkpoint blobs (S3)
- `consistency-coordination` — lease conditional writes
- `sequencer` — run_id, step_id generation
- `human-in-the-loop` — approval park/resume flows
- `llm-gateway` — model calls from the step loop
- `tool-registry-gateway` — tool calls from the step loop
- `observability` — one trace per run with step spans
- `agent-eval-deploy` — version pinning in run state
