#!/usr/bin/env bash
# Drive the whole two-sided Bridge flow through the real REST API, as two
# genuinely different logged-in users.
#
# This is the proof that the walkers coordinate through the graph and not
# through each other: Maria's plan changes because of a walker Sam ran, in a
# separate session, against a separate root.
#
#   ./scripts/seed_demo.sh && ./scripts/demo_flow.sh

set -uo pipefail
cd "$(dirname "$0")/.."
BASE="${BRIDGE_URL:-http://localhost:8000}"
PASSWORD="bridge1234"
FMT="python3 scripts/_fmt.py"

tok() {
  curl -s -X POST "$BASE/user/login" -H 'Content-Type: application/json' \
    -d "{\"identity\":{\"type\":\"email\",\"value\":\"$1\"},
         \"credential\":{\"type\":\"password\",\"password\":\"$PASSWORD\"}}" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["data"]["token"])'
}

spawn() { # spawn <token> <Walker> <json-body>
  curl -s -X POST "$BASE/walker/$2" \
    -H "Authorization: Bearer $1" -H 'Content-Type: application/json' -d "$3"
}

hr() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

MARIA="$(tok maria@bridge.demo)"
SAM="$(tok sam@bridge.demo)"
if [ -z "$MARIA" ] || [ -z "$SAM" ]; then
  echo "Could not log in. Run ./scripts/seed_demo.sh first."
  exit 1
fi

SITUATION='I need food for me and my two kids this week. I lost my ID when we left the apartment, I do not have a car, and where we are staying has no stove. We also got an eviction notice for the room we are in. Zip is 94110.'

hr "1. Maria describes her situation  (IntakeWalker -> EligibilityPathWalker -> NeedBroadcastWalker)"
spawn "$MARIA" IntakeWalker "{\"situation\":\"$SITUATION\"}" | $FMT board

hr "2. What Sam is allowed to see  (CommunityBoard)"
spawn "$SAM" CommunityBoard '{}' | $FMT cards

hr "3. Sam runs the matcher  (MatchWalker - fit, not category equality)"
spawn "$SAM" MatchWalker '{}' | $FMT matches

hr "4. Maria's plan rewrites itself  (FulfillmentWalker, in HER session)"
spawn "$MARIA" FulfillmentWalker '{}' | $FMT board

hr "5. 48h pass with nothing for the shelter need  (FollowUpWalker)"
spawn "$SAM" FollowUpWalker '{"simulate_hours":48}' | $FMT escalations

hr "The shared log every walker wrote to"
spawn "$SAM" CommunityBoard '{}' | $FMT activity
echo
