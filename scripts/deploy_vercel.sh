#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

BACKEND_URL="${1:-${BRIDGE_BACKEND_URL:-}}"

if [ -z "$BACKEND_URL" ]; then
  echo "Usage: BRIDGE_BACKEND_URL=https://bridge-api.example.com $0"
  echo "   or: $0 https://bridge-api.example.com"
  exit 2
fi

./scripts/prepare_vercel.sh "$BACKEND_URL"

echo
echo "Deploying the prepared frontend and proxy configuration..."
npx --yes vercel@latest deploy --cwd .vercel-output --prod
