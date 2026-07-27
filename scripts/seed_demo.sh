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

if [ -n "${BRIDGE_ORG_ACCESS_CODE:-}" ]; then
  echo "  bayview@bridge.demo -> organization"
  sam_token="$(login_token "sam@bridge.demo")"
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
echo "  maria@bridge.demo / $PASSWORD   (person in need)"
echo "  sam@bridge.demo   / $PASSWORD   (volunteer)"
if [ -n "${BRIDGE_ORG_ACCESS_CODE:-}" ]; then
  echo "  bayview@bridge.demo / $PASSWORD   (organization)"
fi
