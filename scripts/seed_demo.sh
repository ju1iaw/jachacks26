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
SEEKER_PASSWORD="bridge::seeker::email-only::maria@bridge.demo"

register() {
  local password="${2:-$PASSWORD}"
  curl -s -X POST "$BASE/user/register" \
    -H 'Content-Type: application/json' \
    -d "{\"identities\":[{\"type\":\"email\",\"value\":\"$1\"}],
         \"credential\":{\"type\":\"password\",\"password\":\"$password\"}}" >/dev/null
}

login_token() {
  local password="${2:-$PASSWORD}"
  curl -s -X POST "$BASE/user/login" \
    -H 'Content-Type: application/json' \
    -d "{\"identity\":{\"type\":\"email\",\"value\":\"$1\"},
         \"credential\":{\"type\":\"password\",\"password\":\"$password\"}}" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["data"]["token"])'
}

set_role() {
  curl -s -X POST "$BASE/function/choose_role" \
    -H "Authorization: Bearer $2" -H 'Content-Type: application/json' \
    -d "{\"role\":\"$3\",\"display_name\":\"$4\"}" >/dev/null
}

echo "seeding the commons..."
curl -s -X POST "$BASE/function/bootstrap" -H 'Content-Type: application/json' -d '{}' >/dev/null

echo "  maria@bridge.demo -> seeker (email-only)"
register "maria@bridge.demo" "$SEEKER_PASSWORD"
maria_token="$(login_token "maria@bridge.demo" "$SEEKER_PASSWORD")"
if [ -n "$maria_token" ]; then
  set_role "maria@bridge.demo" "$maria_token" "seeker" "Maria"
else
  echo "    ! could not log in as maria@bridge.demo"
fi

echo "  sam@bridge.demo -> helper"
register "sam@bridge.demo"
sam_token="$(login_token "sam@bridge.demo")"
if [ -n "$sam_token" ]; then
  set_role "sam@bridge.demo" "$sam_token" "helper" "Sam"
else
  echo "    ! could not log in as sam@bridge.demo"
fi

if [ -n "${BRIDGE_ORG_ACCESS_CODE:-}" ]; then
  echo "  bayview@bridge.demo -> organization"
  org_id="$(
    curl -s -X POST "$BASE/walker/CommunityBoard" \
      -H "Authorization: Bearer $sam_token" \
      -H 'Content-Type: application/json' -d '{}' \
    | python3 -c 'import sys,json; rows=json.load(sys.stdin)["data"]["reports"][0]["orgs"]; print(next(x["org_id"] for x in rows if x["name"]=="Bayview Free Pantry"))'
  )"
  register "bayview@bridge.demo"
  org_token="$(login_token "bayview@bridge.demo")"
  set_role "bayview@bridge.demo" "$org_token" "helper" "Bayview team"
  curl -s -X POST "$BASE/function/activate_organization" \
    -H "Authorization: Bearer $org_token" -H 'Content-Type: application/json' \
    -d "{\"org_id\":\"$org_id\",\"access_code\":\"$BRIDGE_ORG_ACCESS_CODE\"}" >/dev/null
else
  echo "  organization demo skipped (set BRIDGE_ORG_ACCESS_CODE on server and in this shell)"
fi

echo
echo "Demo accounts ready at $BASE"
echo "  maria@bridge.demo                (person in need, email-only)"
echo "  sam@bridge.demo   / $PASSWORD   (volunteer)"
if [ -n "${BRIDGE_ORG_ACCESS_CODE:-}" ]; then
  echo "  bayview@bridge.demo / $PASSWORD   (organization)"
fi
