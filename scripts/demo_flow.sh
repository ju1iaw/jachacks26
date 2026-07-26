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

hr "1. Maria describes her situation  (IntakeWalker -> EligibilityPathWalker -> NeedBroadcastWalker -> StrategyWalker)"
INTAKE="$(spawn "$MARIA" IntakeWalker "{\"situation\":\"$SITUATION\"}")"
echo "$INTAKE" | $FMT board

hr "2. The one thing the caseworker agent could not settle by itself"
# This comes off the SAME response as step 1 -- the question is a field on the
# strategy brief, not a second round trip to the model.
echo "$INTAKE" | $FMT question

hr "3. Maria answers, and the whole chain re-runs on it  (AnswerWalker)"
# Not a stored answer: intake re-reads her enriched story, every gate is re-judged
# against it, the needs are rebuilt and the agent re-plans. Watch the orgs that
# demand paperwork move down and the no-barrier ones move up.
#
# A plain "no", because the agent picks its own question from its research -- a
# reply tailored to one gate would not fit whichever one it actually chose.
spawn "$MARIA" AnswerWalker \
  '{"answer":"No -- I lost everything when we left, so I do not have that."}' | $FMT board

hr "4. What Sam is allowed to see  (CommunityBoard)"
# Note the statuses: the needs that the standing pledges could cover are ALREADY
# matched. Nobody ran a matcher -- NeedBroadcastWalker woke it as each need
# landed, inside Maria's own requests above.
spawn "$SAM" CommunityBoard '{}' | $FMT cards

hr "5. Sam pledges something  (PledgeWalker - and the match happens on arrival)"
ORG="$(spawn "$SAM" CommunityBoard '{}' \
  | python3 -c 'import sys,json; v=json.load(sys.stdin)["data"]["reports"][0]; print(next(o["org_id"] for o in v["orgs"] if o["name"]=="Bayview Free Pantry"))')"
spawn "$SAM" PledgeWalker "{\"kind\":\"food\",
  \"description\":\"6 ready-to-eat family dinners, delivered, no cooking required\",
  \"capacity\":6,\"org_id\":\"$ORG\",\"notes\":\"I can drop these at the pantry or deliver.\"}" >/dev/null
spawn "$SAM" CommunityBoard '{}' | $FMT matches

hr "6. Maria's plan rewrites itself  (FulfillmentWalker, in HER session)"
spawn "$MARIA" FulfillmentWalker '{}' | $FMT board

hr "7. 48h pass with nothing for the shelter need  (FollowUpWalker)"
spawn "$SAM" FollowUpWalker '{"simulate_hours":48}' | $FMT escalations

hr "The shared log every walker wrote to"
spawn "$SAM" CommunityBoard '{}' | $FMT activity
echo
