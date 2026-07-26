"""Bridge - the ReAct caseworker.

This is the one place in Bridge where the model is not answering a single
well-posed question. It is given a person's situation, a set of **tools that
read the live graph**, and a goal -- and it decides for itself what to look up
before committing to a strategy.

    plan_strategy()
       |
       |-- survey_orgs("food")         -> which orgs exist, what they demand
       |-- inspect_gate("photo ID")    -> is there a published workaround?
       |-- check_shelf("food")         -> is the community holding anything usable?
       |-- commons_pressure("food")    -> how many others are asking for this?
       |
       +-> StrategyBrief: ordered actions, the one thing to do first, and the
           risk of doing it in that order

Two things make this more than a wrapper:

  * **The tools traverse the graph.** They are not stubs returning canned text --
    each one runs a real `[root.shared -->...]` read, so the agent's research is
    grounded in the same nodes the walkers act on. Change the graph and the
    agent's plan changes with it.
  * **The reasoning trace is recorded.** Every tool invocation appends to
    `TOOL_TRACE`, which walkers drain into `Activity` nodes. The demo can show
    the agent's actual research path -- which tools it chose, in what order, and
    what came back -- instead of asserting that it planned.

`core/reason.jac` holds the eight single-shot roles; this module holds the one
role that plans. It lives separately because its tools need the graph, and
`reason.jac` is deliberately graph-free so `commons.jac` can import it.
"""

import from core.graph { Contribution, Need, Org, Requirement, Requires, RoutedThrough }
import from core.commons { all_orgs }
import from core.reason {
    ENGINE, _degrade, _fallback_used, _note, live
}


# ---------------------------------------------------------------------------
# The reasoning trace
# ---------------------------------------------------------------------------

"""Tool calls the agent chose to make, in order. Drained into the Activity feed."""
glob TOOL_TRACE: list[str] = [];

glob TOOL_TRACE_CAP: int = 24;


def _trace(call: str, result: str) {
    if len(TOOL_TRACE) < TOOL_TRACE_CAP {
        TOOL_TRACE.append(f"{call} -> {result}");
    }
    print(f"[bridge] agent tool: {call} -> {result}");
}


"""Hand the agent's research path to whoever will write it to the graph."""
def drain_tool_trace -> list[str] {
    lines = list(TOOL_TRACE);
    TOOL_TRACE.clear();
    return lines;
}


# ---------------------------------------------------------------------------
# The tools -- every one of these is a real graph read
# ---------------------------------------------------------------------------

def survey_orgs(category: str) -> str {
    hits: list[str] = [];
    for org in all_orgs() {
        if org.category != category {
            continue;
        }
        gates = [r.label for r in [org ->:Requires:->]];
        demand = "; ".join(gates) if gates else "no eligibility gates";
        hits.append(f"{org.name} (tier {org.tier}, zip {org.zip_prefix if org.zip_prefix else 'any'}, {org.hours}) requires: {demand}");
    }
    if not hits {
        _trace(f"survey_orgs({category})", "0 orgs");
        return f"No organisations in the '{category}' category.";
    }
    _trace(f"survey_orgs({category})", f"{len(hits)} orgs");
    return "\n".join(hits);
}

sem survey_orgs = "List every organisation in a category of help, with the eligibility requirements each one enforces and its service area and hours. Use this to find out what a person will actually be asked for at the door.";
sem survey_orgs.category = "One of 'food', 'shelter', 'legal', 'jobs'.";


def inspect_gate(requirement_fragment: str) -> str {
    needle = requirement_fragment.lower();
    found: list[str] = [];
    for org in all_orgs() {
        for gate in [org ->:Requires:->] {
            if needle in gate.label.lower() {
                fix = gate.workaround if gate.workaround else "no published workaround";
                found.append(f"{org.name} requires '{gate.label}' ({gate.kind}). Workaround: {fix}");
            }
        }
    }
    if not found {
        _trace(f"inspect_gate({requirement_fragment})", "no matching gate");
        return f"No organisation records a requirement matching '{requirement_fragment}'.";
    }
    _trace(f"inspect_gate({requirement_fragment})", f"{len(found)} gate(s)");
    return "\n".join(found);
}

sem inspect_gate = "Look up a specific eligibility requirement across all organisations and return the published workaround for clearing it, if any exists. Use this when a person is blocked by a document or appointment to find out how they can unblock themselves.";
sem inspect_gate.requirement_fragment = "Part of the requirement's name, e.g. 'photo ID', 'social security', 'appointment', 'income'.";


def check_shelf(category: str) -> str {
    shelf: list[str] = [];
    for pledge in [root.shared --> [?:Contribution]] {
        if pledge.remaining <= 0 {
            continue;
        }
        via = [o.name for o in [pledge ->:RoutedThrough:->]];
        if pledge.kind == category or category == "any" {
            note = f" ({pledge.notes})" if pledge.notes else "";
            shelf.append(
                f"{pledge.remaining} of {pledge.capacity} left: {pledge.description}{note}"
                f" via {via[0] if via else 'unrouted'}"
            );
        }
    }
    if not shelf {
        _trace(f"check_shelf({category})", "nothing available");
        return f"The community has nothing available in '{category}' right now.";
    }
    _trace(f"check_shelf({category})", f"{len(shelf)} pledge(s)");
    return "\n".join(shelf);
}

sem check_shelf = "Check what the community has actually pledged and still has available in a category, including any constraints the donor attached. Use this to find out whether a need could be covered by a donation instead of by an organisation visit.";
sem check_shelf.category = "One of 'food', 'shelter', 'legal', 'jobs', or 'any' for everything on the shelf.";


def commons_pressure(category: str) -> str {
    open_now = 0;
    matched = 0;
    for need in [root.shared --> [?:Need]] {
        if need.category != category {
            continue;
        }
        if need.status == "open" {
            open_now += 1;
        } elif need.status in ["matched", "fulfilled"] {
            matched += 1;
        }
    }
    _trace(f"commons_pressure({category})", f"{open_now} open / {matched} served");
    return (
        f"In '{category}': {open_now} need(s) currently open and unmatched, "
        f"{matched} already matched or fulfilled."
    );
}

sem commons_pressure = "Report how many other anonymized needs are competing for help in a category right now. Use this to judge whether to rely on a community donation or send the person straight to an organisation.";
sem commons_pressure.category = "One of 'food', 'shelter', 'legal', 'jobs'.";


# ---------------------------------------------------------------------------
# The agent
# ---------------------------------------------------------------------------

obj StrategyBrief {
    has headline: str;
    has first_action: str;
    has ordered_actions: list[str];
    has rely_on_community: bool;
    has risk: str;
    has research_note: str;
}

sem StrategyBrief = "A caseworker's strategy for getting one person out of an acute crisis, written after researching what local organisations actually require and what the community currently has on hand.";
sem StrategyBrief.headline = "One warm second-person sentence naming the plan's core move. Under 20 words.";
sem StrategyBrief.first_action = "The single thing this person should do first, phrased as a concrete instruction under 25 words. This must be the action that unblocks the most other actions.";
sem StrategyBrief.ordered_actions = "The full sequence of actions in the order they must happen, each under 20 words. Order matters: anything that unblocks another step comes before it. Between 2 and 6 items.";
sem StrategyBrief.rely_on_community = "True if a community donation currently on the shelf is the faster path than an organisation visit, based on what check_shelf reported.";
sem StrategyBrief.risk = "The single most likely way this plan fails, and the hedge against it. One sentence.";
sem StrategyBrief.research_note = "One sentence naming what you looked up and what surprised you, for the caseworker's records.";

def plan_strategy(
    situation: str,
    categories: str,
    assets: str,
    household: int,
    zip_prefix: str
) -> StrategyBrief by llm(
    tools=[survey_orgs, inspect_gate, check_shelf, commons_pressure],
    max_react_iterations=4,
    temperature=0.2
);
sem plan_strategy = "You are an experienced crisis caseworker. Research this person's options using your tools before you commit to anything: find out what the local organisations in their categories actually require at the door, whether any blocking requirement has a published workaround, and whether the community already has something usable on the shelf. Then produce an ordered strategy whose first step unblocks the most other steps. Do not guess at what organisations require -- look it up.";
sem plan_strategy.situation = "The person's own description of their circumstances.";
sem plan_strategy.categories = "Categories of help they need, comma-separated, most urgent first.";
sem plan_strategy.assets = "Documents and resources they confirmed having, comma-separated.";
sem plan_strategy.household = "How many people the plan has to cover.";
sem plan_strategy.zip_prefix = "First three digits of their ZIP, or empty if unknown.";


# ---------------------------------------------------------------------------
# Fallback
# ---------------------------------------------------------------------------

def heuristic_strategy(
    situation: str,
    categories: str,
    assets: str,
    household: int,
    zip_prefix: str
) -> StrategyBrief {
    _ = (situation, zip_prefix);
    cats = [c.strip() for c in categories.split(",") if c.strip()];
    lead = cats[0] if cats else "food";
    have_id = "photo id" in assets.lower();

    actions: list[str] = [];
    if not have_id {
        actions.append("Get a free state photo ID -- most organisations ask for one at the door.");
    }
    for cat in cats[:3] {
        actions.append(f"Visit the nearest {cat} organisation that has no appointment requirement.");
    }
    if not actions {
        actions.append("Visit the nearest no-barrier pantry.");
    }

    return StrategyBrief(
        headline=f"Start with {lead}, and clear your paperwork blocker first.",
        first_action=actions[0],
        ordered_actions=actions,
        rely_on_community=False,
        risk="Walk-in hours may have passed for today; call ahead before travelling.",
        research_note=f"Deterministic fallback plan for a household of {household} -- the model was not reached."
    );
}


def plan_strategy_safe(
    situation: str,
    categories: str,
    assets: str,
    household: int,
    zip_prefix: str
) -> StrategyBrief {
    if live() {
        try {
            _note("plan_strategy");
            return plan_strategy(situation, categories, assets, household, zip_prefix);
        } except Exception as e {
            _degrade("plan_strategy", str(e));
        }
    }
    _fallback_used("plan_strategy");
    return heuristic_strategy(situation, categories, assets, household, zip_prefix);
}
