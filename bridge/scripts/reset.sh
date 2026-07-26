#!/usr/bin/env bash
# Wipe the persistent graph and start over with fresh demo accounts.
#
#   ./scripts/reset.sh          # then re-run jac start
#
# The graph persists in .jac/ between runs, which is the point -- but before a
# demo you usually want a clean board.

set -uo pipefail
cd "$(dirname "$0")/.."

# Pick up OPENAI_API_KEY (or any other model key) if there is a .env.
if [ -f .env ]; then
  set -a; . ./.env; set +a
fi
if [ -n "${OPENAI_API_KEY:-}${ANTHROPIC_API_KEY:-}${GOOGLE_API_KEY:-}" ]; then
  echo "model key found -- byLLM reasoning is ON"
else
  echo "no model key -- running on deterministic heuristics"
fi

echo "stopping any running server on :8000..."
lsof -ti :8000 2>/dev/null | xargs kill -9 2>/dev/null
sleep 1

echo "wiping the graph..."
rm -rf .jac

echo "starting the server..."
jac start --dev main.jac > /tmp/bridge.log 2>&1 < /dev/null &
for _ in $(seq 1 40); do
  sleep 1
  if curl -s -o /dev/null http://localhost:8000/; then break; fi
done

./scripts/seed_demo.sh
