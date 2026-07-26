"""Pretty-print Bridge walker responses for scripts/demo_flow.sh."""

import json
import sys


def board(payload):
    b = payload["data"]["reports"][0]
    print("  engine:", b["engine"])
    print(" ", b["headline"])
    if b["nudge"]:
        print(" ", b["nudge"])
    print()
    for s in b["steps"]:
        print("  [%-9s] %s" % (s["status"], s["title"]))
        if s["blocker"]:
            print("               gate: %s" % s["blocker"])
    if b["needs"]:
        print("\n  anonymized onto the commons:")
        for n in b["needs"]:
            print("    %s  %s" % (n["code"], n["summary"]))


def cards(payload):
    v = payload["data"]["reports"][0]
    for n in v["needs"]:
        print("  %s  %-10s %s" % (n["code"], n["status"], n["summary"]))
    if v["needs"]:
        fields = sorted(k for k in v["needs"][0] if not k.startswith("_"))
        print("\n  every field on this payload:")
        print("   ", ", ".join(fields))
        print("  (nothing here can hold a name, an address or a contact)")


def matches(payload):
    d = payload["data"]
    for n in d["reports"]:
        print("  MATCHED %s -> %s" % (n["code"], n["matched_with"]))
        print("          %s" % n["match_rationale"])
    for note in d["result"].get("notes", []):
        print("  PASSED  %s" % note)
    if not d["reports"]:
        print("  nothing on the shelf fit any open need")


def escalations(payload):
    rows = payload["data"]["reports"]
    if not rows:
        print("  nothing has been unfilled long enough to escalate")
    for n in rows:
        print("  %s escalation #%d -> radius tier %d, urgency now %s"
              % (n["code"], n["escalations"], n["broadcast_tier"], n["urgency"]))


def activity(payload):
    v = payload["data"]["reports"][0]
    for a in reversed(v["activity"]):
        print("  %-22s %s" % (a["walker"], a["detail"]))


MODES = {
    "board": board,
    "cards": cards,
    "matches": matches,
    "escalations": escalations,
    "activity": activity,
}

if __name__ == "__main__":
    raw = sys.stdin.read()
    try:
        parsed = json.loads(raw)
    except ValueError:
        print("  ! server did not return JSON:", raw[:200])
        sys.exit(1)
    if not parsed.get("ok"):
        print("  ! walker error:", parsed.get("error"))
        sys.exit(1)
    MODES[sys.argv[1]](parsed)
