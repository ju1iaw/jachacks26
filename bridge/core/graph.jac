"""Bridge - the graph.

Everything in Bridge is one persistent graph. Two populations live in it:

  * the *seeker* side   -- Person -> PlanStep, Person -> Need
  * the *community* side -- Donor -> Contribution -> Org, Org -> Requirement

They meet at exactly one place: the `Need` node, which an `Org` sits between.

The privacy model is a property of this topology, not a policy bolted on top:

  * There is no edge type in this file whose source is a `Donor`/`Contribution`
    and whose target is a `Person`. The one edge that connects the two worlds --
    `HasNeed` -- points Person -> Need, so it is only traversable *from* the
    person, never back into them from the donor side of the board.
  * The two identity-bearing nodes (`Person`, `Donor`) live on their owner's
    **private root** and are never granted. Everything that has to be shared
    (`Org`, `Requirement`, `Need`, `Contribution`) lives on `root.shared`. So
    the isolation is enforced by the runtime's permission model, not by us
    remembering to filter a field.
  * `NeedCard` -- the only shape the donor side ever receives -- has no field
    that could hold a person.
"""

import from datetime { datetime, timedelta }


# ---------------------------------------------------------------------------
# Seeker side
# ---------------------------------------------------------------------------

node Account {
    """Which side of Bridge this logged-in user is on. Lives on their own root."""

    has role: str;
    has display_name: str;
    has contact_method: str = "";
    has contact_value: str = "";
    has location: str = "";
}


node Person {
    """One human in an acute situation. The only node holding anything personal.

    Lives on the seeker's private root and is never `grant`ed, so no donor
    session can reach it even with its jid.
    """

    has alias: str;
    has situation: str;
    has zip_prefix: str = "";
    has household: int = 1;
    has assets: list[str] = [];
    has anon_summary: str = "";
    has headline: str = "";
    has urgency: str = "medium";
    has categories: list[str] = [];
    has created_at: str = "";
    has last_nudge: str = "";

    # Set by the privacy auditor (reason.jac role 2) before `anon_summary` is
    # allowed onto the commons. `anon_leaks` records what the auditor caught, so
    # the demo can show the repair actually happening rather than claim it.
    has anon_audited: bool = False;
    has anon_leaks: list[str] = [];
}


node AnsweredQuestion {
    """One question the caseworker agent asked, and what the person said back.

    Kept on the graph rather than folded away for two reasons: the agent is handed
    the list so it never asks the same thing twice, and the pair is the audit
    trail for *why* a plan changed between two versions.
    """

    has question: str;
    has answer: str;
    has at: str = "";
}


node CaseStrategy {
    """The ReAct caseworker's brief for one person.

    `research_path` is the agent's own tool trace -- which graph reads it chose
    to make, in order. It is stored rather than logged so the plan can be
    audited after the fact: the strategy and the research behind it live on the
    same node.
    """

    has headline: str;
    has first_action: str;
    has ordered_actions: list[str] = [];
    has rely_on_community: bool = False;
    has risk: str = "";
    has research_note: str = "";
    has research_path: list[str] = [];

    # The one thing the agent still wants to know. Non-empty only when the answer
    # would change which orgs this person is sent to, judged against requirements
    # the agent actually looked up -- `question_why` names the gate that hinges on
    # it. This replaced a standalone `ask_clarifying` role that had no access to
    # the org graph and therefore never found a reason to ask anything.
    has open_question: str = "";
    has question_why: str = "";

    has engine: str = "unknown";
    has at: str = "";
}


node PlanStep {
    """One actionable move in the person's live plan.

    `status` is what makes the plan *adaptive* rather than a static list:
    walkers rewrite it as the graph changes underneath the person.
    """

    has title: str;
    has detail: str;
    has category: str;
    has status: str = "open";
    has org_name: str = "";
    has org_address: str = "";
    has org_phone: str = "";
    has blocker: str = "";
    has unblocks: str = "";
    has unblock_category: str = "";
    has reasoning: str = "";
    has engine: str = "unknown";
    has rank: int = 0;
}


# ---------------------------------------------------------------------------
# Community side
# ---------------------------------------------------------------------------

node Org {
    """A food bank / shelter / legal clinic / job center. The trust intermediary.

    Every donation and every need is routed through one of these -- orgs already
    know how to distribute, and they are the only party permitted to hold both
    a distribution relationship and a person's identity.
    """

    has name: str;
    has category: str;
    has zip_prefix: str;
    has address: str;
    has phone: str;
    has hours: str = "";
    has notes: str = "";
    has tier: int = 1;
}


node Requirement {
    """A real eligibility gate an org enforces. What people find out too late."""

    has label: str;
    has kind: str;
    has hard: bool = True;
    has workaround: str = "";
}


node Donor {
    """Somebody local who wants to help. Never linked to a Person, by design."""

    has name: str;
    has zip_prefix: str = "";
}


node Contribution {
    """A pledge. `remaining` is the memory that stops a depleted donor being re-offered."""

    has kind: str;
    has description: str;
    has capacity: int;
    has remaining: int;
    has notes: str = "";
}


# ---------------------------------------------------------------------------
# The boundary object
# ---------------------------------------------------------------------------

node Need {
    """An anonymized, currently-live need. The ONLY thing that crosses the boundary.

    Deliberately has no name, no address, no contact -- just a category, a
    stripped one-line summary, a household size and a 3-digit zip prefix.
    `code` is the sole handle a donor ever sees.
    """

    has category: str;
    has summary: str;
    has urgency: str;
    has zip_prefix: str;
    has household: int = 1;
    has status: str = "open";
    has code: str = "";
    has created_at: str = "";
    has broadcast_tier: int = 1;
    has escalations: int = 0;
    has fulfillment_note: str = "";
}


node Seeded {
    """Marker so seeding is idempotent across restarts of the persistent graph."""

    has version: str;
}


node Activity {
    """One line of the live walker log. Written by walkers, read by both views.

    This is the demo's proof that the walkers are coordinating through shared
    graph state rather than calling each other: every entry was appended by a
    different walker, in a different request, sometimes by a different user.
    """

    has walker: str;
    has detail: str;
    has at: str;
    has seq: int = 0;
}


# ---------------------------------------------------------------------------
# Edges
# ---------------------------------------------------------------------------

edge HasStep: Person --> PlanStep {}

edge HasNeed: Person --> Need {}

edge HasStrategy: Person --> CaseStrategy {}

edge HasAnswer: Person --> AnsweredQuestion {}

edge Requires: Org --> Requirement {}

edge BroadcastTo: Need --> Org {
    has tier: int = 1;
}

edge Pledges: Donor --> Contribution {}

edge RoutedThrough: Contribution --> Org {}

edge Matched: Need --> Contribution {
    # The pledge's description is copied onto the edge rather than read back off
    # the Contribution: the two nodes have different owners under the server's
    # per-user permission model, so the edge is the one place both sides can
    # reliably see the match.
    has pledge_desc: str = "";
    has rationale: str = "";
    has units: int = 1;
    has score: int = 0;
    has engine: str = "unknown";
    has at: str = "";
}


# ---------------------------------------------------------------------------
# View models -- what actually leaves the server
# ---------------------------------------------------------------------------

obj WalkerTrace {
    """A line in the live activity log the demo shows -- which walker did what."""

    has walker: str;
    has detail: str;
    has at: str = "";
}


obj NeedCard {
    """The donor-facing projection of a Need.

    This type is the enforcement point for the privacy claim: it is structurally
    incapable of carrying a person. The community board endpoint returns
    `list[NeedCard]`, never `list[Need]` and never a `Person`.
    """

    has code: str;
    has category: str;
    has summary: str;
    has urgency: str;
    has zip_prefix: str;
    has household: int;
    has status: str;
    has via_org: str;
    has broadcast_tier: int;
    has escalations: int;
    has matched_with: str = "";
    has match_rationale: str = "";
    has age_label: str = "";
}


obj PledgeCard {
    has pledge_id: str;
    has kind: str;
    has description: str;
    has capacity: int;
    has remaining: int;
    has via_org: str;
    has notes: str = "";
    has mine: bool = False;
}


obj OrgCard {
    has org_id: str;
    has name: str;
    has category: str;
    has address: str;
    has phone: str;
    has hours: str;
    has tier: int;
    has requirements: list[str] = [];
}


obj StrategyView {
    """The ReAct caseworker's brief, including the research path behind it."""

    has headline: str = "";
    has first_action: str = "";
    has ordered_actions: list[str] = [];
    has rely_on_community: bool = False;
    has risk: str = "";
    has research_note: str = "";
    has research_path: list[str] = [];
    has open_question: str = "";
    has question_why: str = "";
    has engine: str = "";
    has at: str = "";
}


obj EngineReport {
    """What is actually answering questions, carried to both UIs verbatim.

    Flat scalars rather than a nested object on purpose: these are rendered as a
    badge, and a judge asking "is that really the model?" should be able to read
    the live call count off the screen.
    """

    has mode: str = "unknown";
    has model: str = "";
    has reason: str = "";
    has calls: int = 0;
    has failures: int = 0;
    has roles: list[str] = [];
}


obj AccountView {
    has role: str;
    has display_name: str;
    has engine: str;
    has engine_model: str = "";
    has engine_reason: str = "";
    has engine_calls: int = 0;
    has engine_roles: list[str] = [];
    has contact_method: str = "";
    has contact_value: str = "";
    has location: str = "";
}


obj CommunityView {
    """Everything the volunteer/donor side sees. Contains no `Person`, by type."""

    has display_name: str;
    has needs: list[NeedCard] = [];
    has pledges: list[PledgeCard] = [];
    has orgs: list[OrgCard] = [];
    has open_count: int = 0;
    has matched_count: int = 0;
    has fulfilled_count: int = 0;
    has activity: list[WalkerTrace] = [];
    has engine: str = "unknown";
    has engine_model: str = "";
    has engine_reason: str = "";
    has engine_calls: int = 0;
    has engine_roles: list[str] = [];
}


obj SeekerBoard {
    """Everything the person in crisis sees. Never leaves for the donor side."""

    has person_id: str;
    has alias: str;
    has headline: str;
    has nudge: str;
    has situation: str = "";
    has steps: list[PlanStep] = [];
    has needs: list[NeedCard] = [];
    has activity: list[WalkerTrace] = [];
    has engine: str = "unknown";
    has has_plan: bool = False;

    # 0 or 1 element. A list rather than an optional so the client can render it
    # with the same map() it uses for every other collection.
    has strategy: list[StrategyView] = [];

    # "question -> answer" for every question already answered, oldest first.
    # The live question itself rides on `strategy[0].open_question`, next to the
    # research that justifies it.
    has answered: list[str] = [];

    # What the privacy auditor caught and repaired before publishing.
    has privacy_leaks: list[str] = [];

    has engine_model: str = "";
    has engine_reason: str = "";
    has engine_calls: int = 0;
    has engine_roles: list[str] = [];
}


# ---------------------------------------------------------------------------
# Small shared helpers
# ---------------------------------------------------------------------------

def now_iso -> str {
    return datetime.now().isoformat(timespec="seconds");
}


def need_code(anchor: str) -> str {
    tail = anchor.replace("-", "").upper();
    return "N-" + tail[-4:] if len(tail) >= 4 else "N-0001";
}


def age_hours(created_at: str) -> float {
    try {
        started = datetime.fromisoformat(created_at);
    } except Exception {
        return 0.0;
    }
    return (datetime.now() - started).total_seconds() / 3600.0;
}


def age_label(created_at: str) -> str {
    hours = age_hours(created_at);
    if hours < 1.0 {
        return "just now";
    }
    if hours < 24.0 {
        return f"{int(hours)}h ago";
    }
    return f"{int(hours / 24.0)}d ago";
}


"""Shift a timestamp backwards -- how the demo's 'simulate 48h' button works."""
def rewind(created_at: str, hours: int) -> str {
    try {
        started = datetime.fromisoformat(created_at);
    } except Exception {
        return created_at;
    }
    return (started - timedelta(hours=hours)).isoformat(timespec="seconds");
}
