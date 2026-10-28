---
name: human-in-the-loop
description: This skill should be used when the user needs to design "human-in-the-loop" (HITL) flows, "approval workflows" for agents, "park and resume" execution, "agent approval", "action confirmation", "review before execute", "escalation" policies, "approval timeout", or "batch approval" for agent-proposed actions. Use it whenever an AI agent proposes side-effecting actions that need human sign-off before execution — even if the user only said "a human needs to approve this".
---

# Human-in-the-Loop & Approvals

Design the flow where an agent proposes an action — especially a WRITE side
effect — parks the run, and waits for a human to approve or reject before
executing. This is the trust boundary between AI autonomy and human oversight.
Get it wrong and you either block agents on every trivial action (destroying
throughput) or let them execute dangerous actions unsupervised (destroying
trust).

## When to reach for this
The design includes an AI agent that can take actions with real-world
consequences (sending emails, making payments, modifying records, deploying
code), and some or all of those actions need human review. Reach here the
moment someone says "the agent shouldn't just do it" or asks about "guardrails"
without specifying the approval mechanism.

## When NOT to
An agent that only reads data and produces analysis — no side effects, no
approval needed. Don't add approval flows to READ-only tools; it kills
throughput without adding safety. Also don't design approval flows before
defining which tools have side effects (→ `tool-registry-gateway` for
side-effect classification).

## Clarify first
- **Approval granularity** — per tool call, per tool category (all WRITE tools),
  per risk level, or per dollar amount? Finer granularity = more human burden.
- **Approver identity** — who approves? The user who triggered the run, their
  manager, a specific role, or an on-call team?
- **Approval latency tolerance** — how long can the run wait? Seconds (real-time
  UX), minutes (async workflow), or hours/days (compliance review)?
- **Batch vs individual** — can a human approve multiple proposed actions at
  once, or must each be reviewed individually?
- **Escalation policy** — what happens if the approver doesn't respond within
  the timeout? Escalate, auto-reject, or auto-approve (dangerous)?

## The options

**Approval trigger policies** (define per tenant)

- **Side-effect class** — all WRITE/ADMIN tools require approval; READ tools
  don't. Simple, coarse, but covers the most dangerous actions.
- **Risk score** — assign a risk score to each tool (based on reversibility,
  blast radius, financial impact). Approval required above a threshold.
- **Dollar threshold** — actions exceeding a dollar amount require approval.
  Works for financial agents.
- **Always/never per tool** — tenant-specific overrides. "Tool X always needs
  approval; Tool Y never does." Stored in tenant config
  (→ `data-storage`).
- **First-N-then-trust** — require approval for the first N uses of a tool by
  a new agent version; auto-approve after N successful approvals. Builds
  trust gradually.

**Park and resume mechanism**

1. Agent runtime proposes an action: serializes `{tool, arguments, context}`.
2. Writes a pending approval record to the approval store:
   `{run_id, step_no, proposed_action, status: PENDING, created_at, ttl}`.
3. Sets run status to `WAITING_APPROVAL`. Releases the pod.
   **No compute held during wait.**
4. Notifies the approver (push notification, email, in-app alert) via
   `messaging-streaming`.
5. Approver reviews: sees tool name, arguments, conversation context, and
   the agent's reasoning for proposing the action.
6. Approver decides: `APPROVED`, `REJECTED`, or `MODIFIED` (adjust arguments).
7. On decision: write decision to approval record → enqueue resume event →
   a worker picks up the run, loads state from checkpoint.
8. **Re-authorize on resume:** before executing the approved action, the
   gateway re-checks the user's scopes. Permissions may have changed between
   proposal and approval (→ `agent-security`).

**Approval UX** (what the approver sees)

- **Minimal:** tool name + arguments. Fast to review but lacks context.
- **Contextual:** tool name + arguments + agent's reasoning + relevant
  conversation history + expected outcome. Slower but informed decision.
- **Diff-style:** for data mutations, show before/after. "This will change
  the customer's plan from Basic to Enterprise."

**Timeout and escalation**

- **TTL per approval** — pending approvals expire after a configurable TTL.
  Default: 24 hours for async workflows, 5 minutes for real-time UX.
- **Escalation chain** — on timeout: notify → remind → escalate to next
  approver → auto-reject. Never auto-approve on timeout (dangerous default).
- **SLA tracking** — track approval response time per approver, per tool,
  per tenant. Alert when SLA is at risk (→ `observability`).

**Batch approval**

- When an agent proposes multiple actions in sequence (e.g., "update 50
  customer records"), batch them into a single approval request.
- The approver reviews the batch: approve all, reject all, or cherry-pick.
- Each approved action executes with its own idempotency key
  (→ `agent-runtime`).

## Trade-offs

| Option | What it solves | What it worsens | Change it when |
|---|---|---|---|
| Approve all WRITE tools | Simple, safe, easy to reason about | Blocks trivial writes (e.g., logging); high human burden | Too many approvals → risk-score-based filtering |
| Risk-score-based | Focuses human attention on high-risk actions | Risk scores must be tuned; wrong scores = missed risk | Risk scores are wrong → fall back to approve-all |
| Park and resume | No idle compute during wait | Resume latency; state serialization complexity | Waits are <1 second → just hold the pod |
| Contextual approval UX | Informed decisions; fewer mistakes | More data to review; approval fatigue | Approvers overwhelmed → streamline to minimal UX |
| Auto-reject on timeout | Prevents indefinite run hangs | Legitimate slow approvals rejected | Critical actions → escalate instead of reject |
| Batch approval | Reduces approval fatigue for bulk operations | All-or-nothing risk; harder to review individual items | Items need individual review → break into singles |

## Behavior under stress

- **Approval backlog:** Many runs parked waiting for approval. No compute
  cost (runs are parked), but business impact: work is blocked. **Mitigation:**
  approval backlog depth as an SLI (→ `observability`). Alert when backlog
  exceeds threshold. Escalation chain shortens under load.
- **Approver unavailable:** The designated approver is on vacation. Escalation
  policy kicks in: route to backup approver. If no backup → run times out →
  auto-reject → user notified to retry when an approver is available.
- **Re-authorization failure on resume:** User's permissions changed between
  proposal and approval (they were de-provisioned, or their OAuth token was
  revoked). Run moves to `AUTH_FAILED`. The agent does not execute the
  action, even though it was approved. This is correct: approval ≠
  authorization.
- **Malicious approval:** An approver approves an action they shouldn't have
  (compromised account, social engineering). **Mitigation:** WORM audit log
  captures who approved what. Separation of duties: the approver can't be the
  same user who triggered the run. High-risk tools require two approvals.

## Cross-references
- `agent-runtime` — park/resume mechanism, checkpoint state
- `messaging-streaming` — approval notification delivery
- `data-storage` — approval records (Postgres with tenant RLS)
- `api-design` — approval endpoints (submit, decide, list pending)
- `agent-security` — re-authorization on resume, scope enforcement
- `observability` — approval backlog depth, decision latency SLIs
- `tool-registry-gateway` — side-effect classification drives approval policy
