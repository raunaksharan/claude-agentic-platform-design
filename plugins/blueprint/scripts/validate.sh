#!/usr/bin/env bash
# Validate the Blueprint plugin structure
# Usage: ./scripts/validate.sh

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ERRORS=0

check() {
  if [ ! -e "$PLUGIN_ROOT/$1" ]; then
    echo "✗ Missing: $1"
    ERRORS=$((ERRORS + 1))
  else
    echo "✓ Found:   $1"
  fi
}

echo "Validating Blueprint plugin at: $PLUGIN_ROOT"
echo "────────────────────────────────────────────"

# Core structure
check ".claude-plugin/plugin.json"
check "agents/system-design-orchestrator.md"
check "commands/design.md"

# Infrastructure skills (21)
for skill in system-design requirements-scoping back-of-the-envelope \
  service-decomposition api-design data-storage caching messaging-streaming \
  load-balancing content-delivery dns blob-store distributed-search \
  distributed-logging observability resilience-failure scaling-evolution \
  consistency-coordination sequencer sharded-counters task-scheduling; do
  check "skills/$skill/SKILL.md"
done

# Agent-platform skills (7)
for skill in agent-runtime llm-gateway tool-registry-gateway \
  human-in-the-loop agent-memory agent-security agent-eval-deploy; do
  check "skills/$skill/SKILL.md"
done

echo "────────────────────────────────────────────"
if [ $ERRORS -eq 0 ]; then
  echo "✓ All 31 required files present. Plugin is valid."
else
  echo "✗ $ERRORS file(s) missing."
  exit 1
fi
