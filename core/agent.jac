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
       +-> StrategyBrief: ordered actions, the one thing to do first, the risk
           of doing it in that order, and -- when its research turns up a gate
           whose outcome depends on something the person never said -- the one
           question worth asking them

Two things make this more than a wrapper:

  * **The tools traverse the graph.** They are not stubs returning canned text --
    each one runs a real `[root.shared -->...]` read, so the agent's research is
    grounded in the same nodes the walkers act on. Change the graph and the
    agent's plan changes with it.
  * **The reasoning trace is recorded.** Every tool invocation appends to
    `TOOL_TRACE`, which walkers drain into `Activity` nodes. The demo can show
    the agent's actual research path -- which tools it chose, in what order, and
    what came back -- instead of asserting that it planned.

`core/reason.jac` holds the six single-shot roles; this module holds the one that
plans. It lives separately because its tools need the graph, and `reason.jac` is
deliberately graph-free so `commons.jac` can import it.

The open question lives here rather than in its own role for a reason. It used to
be a standalone `ask_clarifying` call, and it never once fired: it was asked
whether a missing fact "would change which organisations this person is sent to"
while being handed no organisations and no requirements, so it had no basis to
ever answer yes. The judgement needs the org graph, and the agent that already
surveys the gates is the only thing holding it.

What the agent is allowed to ask is then narrowed by a deterministic guard in
`core/question_guard.jac`. A question that collects a street address, or that
hands the research back to the person, is too load-bearing to leave to a line in
a prompt that the model has been observed ignoring.
"""

import from core.graph { Contribution, Need, Org, Requirement, Requires, RoutedThrough }
import from core.commons { all_orgs }
import from core.reason { _note, _note_failure, require_engine }
import from core.question_guard { unfit_question }


# ---------------------------------------------------------------------------
# The reasoning trace
# ---------------------------------------------------------------------------

"""What the agent did, in order -- and what Bridge refused to let it do.

Mostly the tool calls it chose to make, plus any question the guard below withheld.
Drained into the Activity feed and stored on the `CaseStrategy` node.
"""
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
    has open_question: str;
    has question_why: str;
}

sem StrategyBrief = "A caseworker's strategy for getting one person out of an acute crisis, written after researching what local organisations actually require and what the community currently has on hand.";
sem StrategyBrief.headline = "One warm second-person sentence naming the plan's core move. Under 20 words.";
sem StrategyBrief.first_action = "The single thing this person should do first, phrased as a concrete instruction under 25 words. This must be the action that unblocks the most other actions.";
sem StrategyBrief.ordered_actions = "The full sequence of actions in the order they must happen, each under 20 words. Order matters: anything that unblocks another step comes before it. Between 2 and 6 items. Do not number them -- the list order is the order.";
sem StrategyBrief.rely_on_community = "True if a community donation currently on the shelf is the faster path than an organisation visit, based on what check_shelf reported.";
sem StrategyBrief.risk = "The single most likely way this plan fails, and the hedge against it. One sentence.";
sem StrategyBrief.research_note = "One sentence naming what you looked up and what surprised you, for the caseworker's records.";
sem StrategyBrief.open_question = "The single highest-value fact you still do not know, asked directly of the person, warm, under 20 words -- but ONLY when a requirement you actually looked up with your tools hinges on the answer. Leave it empty otherwise: asking someone in crisis a question that does not change their plan is a cost, not a courtesy, and empty is the right answer more often than not. Four hard rules. (1) NEVER ask for anything that identifies them -- no street address, no full ZIP, no name, no phone number, no employer, no school. This person's situation is published anonymously to strangers, and a question that collects an identifying detail breaks the promise the whole service runs on. Ask what they HAVE or CAN GET ('Do you have any photo ID, even an expired one?', 'Can you get a letter from wherever you are staying?') -- never where they are or who they are. (2) Second person, addressed to them: 'Do you have...', 'Is there...', 'Can you...'. They are reading this, so never write about them in the third person. (3) It must be answerable from their own knowledge of their own life. Never ask how to obtain something or where to find something -- that is your job, look it up with your tools. (4) If the answered list already settles the fact, do not ask a rephrased version of it: pick a different requirement, or leave this empty.";
sem StrategyBrief.question_why = "Justify the question by naming the specific organisation(s) and requirement that hinge on it, AND what changes each way. e.g. 'Mission Community Food Bank and two others ask for photo ID at the door -- if you have one you can go tomorrow morning; if not, Bayview Free Pantry takes people with no paperwork at all.' Empty when there is no question.";

def plan_strategy(
    situation: str,
    categories: str,
    assets: str,
    household: int,
    zip_prefix: str,
    already_answered: str
) -> StrategyBrief by llm(
    tools=[survey_orgs, inspect_gate, check_shelf, commons_pressure],
    max_react_iterations=4,
    temperature=0.2
);
sem plan_strategy = "You are an experienced crisis caseworker. Research this person's options using your tools before you commit to anything: find out what the local organisations in their categories actually require at the door, whether any blocking requirement has a published workaround, and whether the community already has something usable on the shelf. Then produce an ordered strategy whose first step unblocks the most other steps. Do not guess at what organisations require -- look it up. If your research turns up a requirement whose outcome depends on something this person has not told you, raise it as the one open question; otherwise leave that empty. You work anonymously: you already have every location detail you are permitted to hold, so never ask this person where they live, where they are staying, or for any other detail that would identify them.";
sem plan_strategy.situation = "The person's own description of their circumstances.";
sem plan_strategy.categories = "Categories of help they need, comma-separated, most urgent first.";
sem plan_strategy.assets = "Documents and resources they confirmed having, comma-separated.";
sem plan_strategy.household = "How many people the plan has to cover.";
sem plan_strategy.zip_prefix = "First three digits of their ZIP. This is deliberately all the location Bridge holds, and it is enough to pick a service area -- treat a residency gate as a question of what paperwork they can get, never of where they actually live.";
sem plan_strategy.already_answered = "Questions this person has already been asked and what they answered, one per line. Treat every answer as established fact, and never ask any of these again -- including rephrasings or follow-ups that hinge on the same fact. If an answer closed off a path (a workaround they cannot reach, a document they do not have), stop planning around that path and route them somewhere that does not need it.";


def plan_strategy_safe(
    situation: str,
    categories: str,
    assets: str,
    household: int,
    zip_prefix: str,
    already_answered: str
) -> StrategyBrief {
    require_engine("plan_strategy");
    try {
        _note("plan_strategy");
        brief = plan_strategy(
            situation, categories, assets, household, zip_prefix, already_answered
        );
    } except Exception as e {
        _note_failure("plan_strategy", str(e));
        raise;
    }

    # The model has been observed breaking the rules on `open_question`, so what
    # it wants to ask is vetted before anyone sees it. See core/question_guard.jac.
    if brief.open_question {
        unfit = unfit_question(brief.open_question);
        if unfit {
            # Recorded in the trace rather than dropped silently: the guard firing
            # is exactly the kind of thing the demo should be able to point at.
            _trace(
                "question withheld",
                f"the agent tried to ask this person {unfit}"
            );
            brief.open_question = "";
            brief.question_why = "";
        }
    }
    return brief;
}
