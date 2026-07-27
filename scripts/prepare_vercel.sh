#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

BACKEND_URL="${1:-${BRIDGE_BACKEND_URL:-}}"
OUTPUT_DIR=".vercel-output"
JAC_DIST=".jac/client/dist"

if [ -z "$BACKEND_URL" ]; then
  echo "Usage: BRIDGE_BACKEND_URL=https://bridge-api.example.com $0"
  echo "   or: $0 https://bridge-api.example.com"
  exit 2
fi

case "$BACKEND_URL" in
  https://*) ;;
  *)
    echo "BRIDGE_BACKEND_URL must be an https:// URL."
    exit 2
    ;;
esac

BACKEND_URL="${BACKEND_URL%/}"

echo "Installing declared client dependencies..."
jac install --npm

echo "Building the static client..."
jac build --client static

test -f "$JAC_DIST/index.html"

mkdir -p "$OUTPUT_DIR/public"
find "$OUTPUT_DIR/public" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -R "$JAC_DIST/." "$OUTPUT_DIR/public/"

python3 - "$BACKEND_URL" "$OUTPUT_DIR/vercel.json" <<'PY'
import json
import sys

backend_url, output_path = sys.argv[1:]
proxy_prefixes = ("user", "walker", "function", "cl")

config = {
    "$schema": "https://openapi.vercel.sh/vercel.json",
    "framework": None,
    "outputDirectory": "public",
    "cleanUrls": True,
    "rewrites": [
        {
            "source": f"/{prefix}/:path*",
            "destination": f"{backend_url}/{prefix}/:path*",
        }
        for prefix in proxy_prefixes
    ]
    + [{"source": "/(.*)", "destination": "/index.html"}],
    "headers": [
        {
            "source": "/(.*)",
            "headers": [
                {"key": "X-Content-Type-Options", "value": "nosniff"},
                {"key": "Referrer-Policy", "value": "strict-origin-when-cross-origin"},
            ],
        }
    ],
}

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(config, handle, indent=2)
    handle.write("\n")
PY

echo
echo "Prepared $OUTPUT_DIR for Vercel."
echo "API requests will proxy to $BACKEND_URL."
