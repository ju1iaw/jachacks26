#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -z "${OPENAI_API_KEY:-}${ANTHROPIC_API_KEY:-}${GOOGLE_API_KEY:-}" ]; then
  echo "Missing model API key. Set OPENAI_API_KEY, ANTHROPIC_API_KEY, or GOOGLE_API_KEY."
  exit 2
fi

if [ -z "${JWT_SECRET:-}" ]; then
  echo "Missing JWT_SECRET. Generate one with: openssl rand -hex 32"
  exit 2
fi

if [ -z "${BRIDGE_ORG_ACCESS_CODE:-}" ]; then
  echo "Missing BRIDGE_ORG_ACCESS_CODE. Generate one with: openssl rand -hex 24"
  exit 2
fi

if [ -z "${MONGODB_URI:-}" ]; then
  echo "Warning: MONGODB_URI is not set; graph data may be lost when the server restarts." >&2
fi

exec jac start main.jac --host 0.0.0.0 --port "${PORT:-8000}"
