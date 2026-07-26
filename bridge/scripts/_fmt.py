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
    if b["answered"]:
        print("\n  what she has been asked, and answered:")
        for row in b["answered"]:
            print("    %s" % row)


def question(payload):
    """The one thing the ReAct agent could not settle by reading the graph.

    It rides on the strategy brief rather than standing alone because the agent
    that surveyed the gates is the only thing that knows which gate hinges on the
    answer -- and `question_why` naming that gate is what makes the question worth
    putting to someone in a crisis.
    """
    b = payload["data"]["reports"][0]
    asked = [s for s in b["strategy"] if s["open_question"]]
    if not asked:
        print("  no open question -- nothing the agent looked up hinged on")
        print("  something she had not already told it")
        return
    for s in asked:
        print("  Q: %s" % s["open_question"])
        print("  because: %s" % s["question_why"])
        if s["research_path"]:
            print("\n  it earned the right to ask by reading the graph first:")
            for call in s["research_path"]:
                print("    %s" % call)


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
    """Matched needs, read off the community board.

    Matching is autonomous now, so there is no MatchWalker response to unwrap --
    the walker ran nested inside PledgeWalker. Both halves of its judgement are
    read back out of shared graph state instead: the matches off the needs, and
    what it declined out of the activity feed it wrote them to.
    """
    v = payload["data"]["reports"][0]
    hits = [n for n in v["needs"] if n["matched_with"]]
    for n in hits:
        print("  MATCHED %s -> %s" % (n["code"], n["matched_with"]))
        print("          %s" % n["match_rationale"])
    for a in reversed(v["activity"]):
        if a["walker"] == "MatchWalker" and ": passed on " in a["detail"]:
            print("  PASSED  %s" % a["detail"])
    if not hits:
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
    "question": question,
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
