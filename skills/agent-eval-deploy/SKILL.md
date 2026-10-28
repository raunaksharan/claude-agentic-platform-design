---
name: agent-eval-deploy
description: This skill should be used when the user needs to design "agent evaluation", "agent testing", "eval gate", "golden task set", "trajectory testing", "agent canary deployment", "agent rollout", "LLM judge", "agent quality metrics", "task success rate", "escalation rate", "agent version management", "auto-rollback" for agents, or "safe deployment" of AI agents. Use it whenever an AI agent version must be tested for quality and safely rolled out to production — even if the user only said "how do we deploy a new agent version safely".
---

# Agent Eval & Safe Deployment

Design how a new agent version is tested for quality before production, and how
it's rolled out with agent-specific safety nets. Traditional canary deployments
check latency and error rate; agent canaries must also check *task success rate*,
*trajectory correctness*, *escalation rate*, and *cost per run*. A new agent
version that's fast and error-free but gives wrong answers or calls the wrong
tools is worse than useless — it's dangerous.

## When to reach for this
The design includes agents that will be updated over time (new prompt versions,
new tools, model upgrades), and you need to decide: how to test a new version
before deploying, how to roll it out gradually, and how to detect and roll back
quality regressions. Reach here the moment someone says "we're updating the
agent" or "how do we know the new version is better" without specifying a
testing or rollout strategy.

## When NOT to
A prototype or internal-only agent with a single user who can manually verify
quality — just deploy and check. Don't build an eval pipeline until you have:
multiple tenants relying on the agent, agent updates that can't be manually
verified, or SLAs on agent quality. Also don't confuse agent eval with model
benchmarking — you're testing *your agent* (prompt + tools + config), not the
underlying model's general capabilities.

## Clarify first
- **What does "correct" mean?** — is there a single right answer, or multiple
  acceptable outcomes? Can correctness be checked programmatically, or does it
  require human/LLM judgment?
- **Trajectory matters** — is the *path* the agent takes important (right tools,
  right order, right arguments), or only the final output?
- **Negative test cases** — are there things the agent must *refuse* to do
  (out-of-scope requests, unauthorized actions, prompt injection attempts)?
- **Eval latency budget** — how fast must eval run? CI blocking (minutes) vs
  nightly batch (hours)?
- **Rollout scope** — deploy to all tenants simultaneously, or tenant-by-tenant?
  Some tenants may be more risk-tolerant (internal) vs less (enterprise).

## The options

**Golden task sets** (the foundation of agent eval)

- **Structure:** Each golden task is:
  - `input`: the user message that starts the run
  - `expected_outcome`: the expected final result (exact match, contains, regex,
    or semantic similarity)
  - `expected_trajectory` (optional): the expected sequence of tool calls, with
    expected arguments (exact or pattern-matched)
  - `expected_refusal` (optional): for negative test cases, the agent should
    refuse and not call certain tools
  - `context` (optional): pre-set memory, user profile, tenant config needed
    for the test
- **Coverage:** Golden sets should cover:
  - Happy path (common tasks that should succeed)
  - Edge cases (unusual inputs, boundary conditions)
  - Permission tests (requests that should be refused)
  - Injection tests (prompt injection attempts that should fail)
  - Multi-step tasks (tasks requiring >3 steps to test the loop)
- **Maintenance:** Golden sets are code, version-controlled alongside the agent.
  When tools change, golden sets must be updated.

**LLM judge** (automated quality scoring)

- A second model (different family from the agent's model, to avoid shared
  biases) scores the agent's output against the expected outcome.
- Scoring rubric: correctness (0–5), completeness (0–5), safety (pass/fail).
- **Calibration:** Run the judge on a set of human-labeled examples. Track
  judge-human agreement rate. If agreement drops below 85%, recalibrate.
- **Cost isolation:** Run eval against a separate provider quota so eval
  traffic can't starve production (→ `llm-gateway`).

**CI eval gate** (block bad deploys)

- Run the golden task set against the new agent version in CI.
- **Gate criteria:**
  - Task success rate ≥ threshold (e.g., 95% for production, 90% for staging)
  - No regression on any permission test (zero-tolerance for auth failures)
  - No regression on any injection test
  - Cost per run ≤ 1.2× the baseline (catch prompt/model changes that
    explode cost)
  - Trajectory similarity ≥ threshold (for trajectory-sensitive tasks)
- **Gate action:** Fail the CI pipeline. The deploy is blocked. The diff shows
  which specific tasks regressed.

**Canary rollout** (gradual production deployment)

- **Traffic split:** Route X% of a tenant cohort to the new version. Start
  at 5%, increase to 25%, 50%, 100% if metrics hold.
- **Agent-specific canary metrics** (in addition to standard latency/error rate):
  - **Task success rate** — % of runs that reach a successful terminal state
  - **Escalation rate** — % of runs that escalate to human or `NEEDS_REVIEW`
  - **Tool error rate** — % of tool calls that fail (schema validation, auth,
    timeout)
  - **Cost per run** — average tokens × price per completed run
  - **Approval rate** — for HITL flows, % of proposed actions approved vs
    rejected (a drop suggests the agent is proposing bad actions)
- **Comparison window:** Compare canary cohort vs control cohort over the same
  time period. Statistical significance test before promoting.

**Version management**

- **Version pinning in run state** — each run records the agent version that
  started it. In-flight runs finish on the version they started, even if a
  new version is deployed mid-run. No mid-run version switches.
- **Deployment pointer** — a per-tenant pointer to the active agent version.
  Canary: the pointer routes a % to the new version. Rollback: flip the
  pointer back. In-flight runs on the old version continue unaffected.
- **Deprecation policy** — old versions are deprecated after N days. Runs on
  deprecated versions are logged. After deprecation + grace period, old
  versions are disabled.

**Auto-rollback**

- If canary metrics breach a threshold during the rollout window:
  - Flip the deployment pointer back to the previous version.
  - In-flight runs on the canary version continue (version pinning) or are
    drained (depends on rollback urgency).
  - Alert fires with the specific metrics that breached.
  - Rollback is logged in the deployment audit trail.
- Rollback triggers: task success rate drops >5%, escalation rate increases
  >10%, cost per run increases >50%, any injection test failure in production.

**K8s integration** (for runtime worker deploys)

- Rolling update with PodDisruptionBudget: at least N workers always available.
- Graceful shutdown: on SIGTERM → finish current step → checkpoint → release
  lease → exit. Don't kill a worker mid-step.
- Readiness probe: worker reports ready only after loading the agent version's
  config and tool schemas.

## Trade-offs

| Option | What it solves | What it worsens | Change it when |
|---|---|---|---|
| Golden task sets | Deterministic, repeatable, version-controlled | Maintenance burden; doesn't catch novel failure modes | Complement with production monitoring |
| LLM judge | Scales beyond hand-labeled test sets | Judge errors; cost of running the judge; bias if same model family | Judge-human agreement drops → recalibrate or add human review |
| CI eval gate | Blocks bad deploys before production | Increases deploy time; flaky evals block good deploys | Flaky tests → quarantine and fix; don't disable the gate |
| Canary rollout | Catches production issues golden sets miss | Slow rollout; canary cohort exposed to potential issues | Uniform tenant base → random split OK; diverse tenants → stratify |
| Version pinning | In-flight runs unaffected by deploys | Old versions accumulate; must maintain compatibility | Aggressive deprecation → force-drain old-version runs |
| Auto-rollback | Limits blast radius of bad deploys | False positive rollbacks; rollback during a brief blip | Too sensitive → widen threshold; too slow → tighten window |

## Behavior under stress

- **Golden set regression on model upgrade:** Provider releases a new model
  version. Agent's golden set scores drop. CI gate blocks the deploy. Team
  investigates: adjust prompts for the new model, update golden set if the
  new behavior is correct, or pin the old model version in the agent config.
- **Canary metric noise:** Canary cohort is too small; metrics are noisy.
  Statistical significance test prevents premature promotion or rollback.
  If unsure, extend the canary window rather than promoting.
- **Eval traffic starves production:** CI eval runs consume LLM tokens.
  Mitigation: separate provider quota for eval (→ `llm-gateway`). Eval
  traffic uses a different API key with its own rate limit. Production is
  unaffected.
- **Rollback cascade:** New version is rolled back, but in-flight runs on the
  new version are still completing. Some succeed, some fail. Version pinning
  ensures consistency: each run finishes on the version it started. Failed
  runs are retried on the rolled-back (old) version.

## Cross-references
- `observability` — canary metrics (task success rate, escalation rate, cost)
- `agent-runtime` — version pinning in run state
- `messaging-streaming` — routing by version (canary traffic split)
- `scaling-evolution` — deployment strategy as a scaling concern
- `llm-gateway` — separate eval quota; model version pinning
- `tool-registry-gateway` — tool version compatibility with agent version
- `agent-security` — injection test cases in golden sets
