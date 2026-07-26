#!/usr/bin/env bash
# Seed the two demo accounts against a running Bridge server.
#
#   jac start --dev main.jac          # in one terminal
#   ./scripts/seed_demo.sh            # in another
#
# Safe to re-run: registration failures on an existing account are ignored,
# and choose_role is idempotent.

set -uo pipefail
BASE="${BRIDGE_URL:-http://localhost:8000}"
PASSWORD="bridge1234"

register() {
  curl -s -X POST "$BASE/user/register" \
    -H 'Content-Type: application/json' \
    -d "{\"identities\":[{\"type\":\"email\",\"value\":\"$1\"}],
         \"credential\":{\"type\":\"password\",\"password\":\"$PASSWORD\"}}" >/dev/null
}

login_token() {
  curl -s -X POST "$BASE/user/login" \
    -H 'Content-Type: application/json' \
    -d "{\"identity\":{\"type\":\"email\",\"value\":\"$1\"},
         \"credential\":{\"type\":\"password\",\"password\":\"$PASSWORD\"}}" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["data"]["token"])'
}

set_role() {
  curl -s -X POST "$BASE/function/choose_role" \
    -H "Authorization: Bearer $2" -H 'Content-Type: application/json' \
    -d "{\"role\":\"$3\",\"display_name\":\"$4\"}" >/dev/null
}

echo "seeding the commons..."
curl -s -X POST "$BASE/function/bootstrap" -H 'Content-Type: application/json' -d '{}' >/dev/null

for spec in "maria@bridge.demo:seeker:Maria" "sam@bridge.demo:helper:Sam"; do
  IFS=":" read -r email role name <<< "$spec"
  echo "  $email -> $role"
  register "$email"
  token="$(login_token "$email")"
  if [ -z "$token" ]; then
    echo "    ! could not log in as $email"
    continue
  fi
  set_role "$email" "$token" "$role" "$name"
done

echo
echo "Demo accounts ready at $BASE"
echo "  maria@bridge.demo / $PASSWORD   (person in need)"
echo "  sam@bridge.demo   / $PASSWORD   (volunteer)"
