"""Bridge - the reasoning layer.

Every judgement Bridge makes about a human being is made by a model, not by a
keyword table. There are **eight distinct LLM roles** here, deliberately not one
prompt reused eight times:

  1. `read_situation`      -- free text -> structured facts + an anonymized
                              one-liner. The anonymization is a reasoning step.
  2. `audit_anonymization` -- a SECOND model pass that tries to find identity
                              leaks in role 1's output before it is published to
                              the commons. The privacy claim is enforced, not
                              asserted.
  3. `ask_clarifying`      -- decides whether one missing fact would change the
                              plan, and asks for exactly that.
  4. `judge_requirement`   -- does this person's situation clear this org's
                              specific eligibility gate, and if not, what single
                              action unblocks it.
  5. `judge_match`         -- soft-matches a live need against a donor pledge on
                              *fit*, not category equality.
  6. `plan_strategy`       -- the ReAct caseworker. Lives in `core/agent.jac`
                              because its tools traverse the graph.
  7. `escalation_strategy` -- when a need goes unanswered, reasons about *how*
                              to widen the ask, not just how far.
  8. `next_step_nudge`     -- the one line the person actually reads when their
                              plan changes underneath them.

## Engine honesty

The old version of this file decided whether the model was available by checking
whether an env var was *set*. That is not the same question as whether the model
*works*, and it meant a typo'd key silently served regex output that looked like
reasoning. Now:

  * `ensure_engine()` makes one real structured `by llm()` call at boot and only
    reports `llm` if the model round-trips a typed object successfully.
  * every fallback increments a counter, logs loudly, and shows up in the UI as
    DEGRADED with the actual provider error attached.
  * `BRIDGE_STRICT_LLM=1` makes the fallbacks *raise* instead of substituting, so
    there is a mode in which no answer can possibly be heuristic.

The deterministic fallbacks below still exist -- a dead API key should not kill a
live demo -- but they are an explicitly-labelled degradation, never a peer of the
model.
"""

import os;
import re;
import from jaclang.byllm.lib { Model }


# ===========================================================================
# Engine state
# ===========================================================================

obj EngineState {
    """What is actually answering questions right now, and how we know."""

    has mode: str = "unknown";
    has model: str = "";
    has reason: str = "";
    has calls: int = 0;
    has failures: int = 0;
    has fallbacks: int = 0;
    has checked: bool = False;
}


glob ENGINE: EngineState = EngineState();

glob _KEY_VARS: list[str] = [
    "OPENAI_API_KEY",
    "ANTHROPIC_API_KEY",
    "GOOGLE_API_KEY",
    "GEMINI_API_KEY",
    "OLLAMA_HOST"
];

"""Role-by-role call tally. Proof, on stage, that every role really fired."""
glob ROLE_CALLS: dict[str, int] = {};

"""Degradation events waiting to be written into the shared Activity feed.

`core/commons.jac` imports from this module, so this module cannot import it
back. Instead walkers drain this list into the graph -- the log surfaces in the
UI without creating a circular import.
"""
glob DEGRADE_LOG: list[str] = [];


def has_key -> bool {
    for var in _KEY_VARS {
        if os.environ.get(var) {
            return True;
        }
    }
    return False;
}


def strict_mode -> bool {
    return os.environ.get("BRIDGE_STRICT_LLM", "") not in ["", "0", "false", "False"];
}


def model_label -> str {
    override = os.environ.get("BYLLM_DEFAULT_MODEL", "");
    return override if override else "gpt-4o-mini";
}


"""The model behind every `by llm()` in this file.

Bound explicitly instead of leaning on the ambient `llm` builtin for two
reasons: `jac.toml`'s `[byllm.model]` default is invisible at the call site, so
"which model is this?" becomes unanswerable by reading the code; and tests need
to swap this for a `MockLLM` to exercise the structured-output path without a
network call. `BYLLM_DEFAULT_MODEL` still overrides it.
"""
glob llm: Model = Model(model_name=model_label());


def _short(text: str) -> str {
    flat = " ".join(text.split());
    return flat if len(flat) <= 160 else flat[:157] + "...";
}


def _push_degrade(where: str, detail: str) {
    line = f"{where}: {detail}";
    DEGRADE_LOG.append(line);
    print(f"[bridge] DEGRADED -- {line}");
}


"""Hand the pending degradation lines to whoever will write them to the graph."""
def drain_degrade_log -> list[str] {
    lines = list(DEGRADE_LOG);
    DEGRADE_LOG.clear();
    return lines;
}


def _note(role: str) {
    ENGINE.calls += 1;
    ROLE_CALLS[role] = ROLE_CALLS.get(role, 0) + 1;
}


def _degrade(role: str, err: str) {
    ENGINE.failures += 1;
    ENGINE.mode = "degraded";
    ENGINE.reason = _short(err);
    _push_degrade(role, ENGINE.reason);
}


def _fallback_used(role: str) {
    ENGINE.fallbacks += 1;
    if strict_mode() {
        raise RuntimeError(
            f"BRIDGE_STRICT_LLM is set, so role '{role}' refuses to answer "
            f"heuristically. Engine is '{ENGINE.mode}': {ENGINE.reason}"
        );
    }
    _push_degrade(role, "answered by deterministic fallback, NOT the model");
}


# ---------------------------------------------------------------------------
# Preflight -- prove the model works before claiming it does
# ---------------------------------------------------------------------------

obj Pong {
    has ok: bool;
    has model_said: str;
}

sem Pong = "A connectivity acknowledgement.";
sem Pong.ok = "Always true.";
sem Pong.model_said = "The single word 'ready'.";

def _preflight_probe(token: str) -> Pong by llm(temperature=0.0, max_tokens=64);
sem _preflight_probe = "A connectivity check. Acknowledge that you received the token.";
sem _preflight_probe.token = "An arbitrary token. Its content does not matter.";


"""Decide once, for real, what is answering questions.

A *typed* probe on purpose: it exercises the whole byLLM path -- auth, request,
schema injection and structured-output parsing -- so a success here means the
eight real roles will also parse, not just that a socket opened.
"""
def ensure_engine -> str {
    if ENGINE.checked {
        return ENGINE.mode;
    }
    ENGINE.checked = True;
    ENGINE.model = model_label();

    if not has_key() {
        ENGINE.mode = "unconfigured";
        ENGINE.reason = "no model API key in the environment (set OPENAI_API_KEY)";
        _push_degrade("preflight", ENGINE.reason);
        return ENGINE.mode;
    }

    try {
        probe = _preflight_probe("ping");
        if probe.ok {
            ENGINE.mode = "llm";
            ENGINE.reason = "";
            _note("preflight");
            print(f"[bridge] byLLM live on {ENGINE.model} -- structured probe round-tripped");
        } else {
            ENGINE.mode = "degraded";
            ENGINE.reason = "model reachable but returned an unusable probe";
            _push_degrade("preflight", ENGINE.reason);
        }
    } except Exception as e {
        ENGINE.mode = "degraded";
        ENGINE.reason = _short(str(e));
        ENGINE.failures += 1;
        _push_degrade("preflight", ENGINE.reason);
    }
    return ENGINE.mode;
}


def live -> bool {
    return ensure_engine() == "llm";
}


"""Back-compat string the views already render."""
def engine -> str {
    return ENGINE.mode if ENGINE.checked else ensure_engine();
}


def engine_state -> EngineState {
    ensure_engine();
    return ENGINE;
}


def role_calls -> dict[str, int] {
    return ROLE_CALLS;
}


# ===========================================================================
# Role 1 - situation intake + anonymization
# ===========================================================================

obj SituationRead {
    has categories: list[str];
    has urgency: str;
    has household: int;
    has zip_prefix: str;
    has assets: list[str];
    has anonymized_summary: str;
    has headline: str;
}

sem SituationRead = "Structured facts pulled out of a person's plain-language description of their crisis.";
sem SituationRead.categories = "Which kinds of help this person needs. Use only these exact values: 'food', 'shelter', 'legal', 'jobs'. Order by urgency, most urgent first. Only include a category they actually need -- mentioning they have no car is a constraint, not a request for shelter.";
sem SituationRead.urgency = "How fast this must be solved. Exactly one of: 'critical' (today/tonight), 'high' (this week), 'medium' (this month), 'low'.";
sem SituationRead.household = "How many people are being fed or housed, including the person themself. Default to 1 if not stated.";
sem SituationRead.zip_prefix = "The first 3 digits of their ZIP code if mentioned, otherwise an empty string. Never the full ZIP.";
sem SituationRead.assets = "Concrete things they say they HAVE that could satisfy an eligibility requirement: e.g. 'state photo ID', 'proof of address', 'social security card', 'car', 'phone', 'bank account'. Only list what they actually claim to have. Never list something they say they lack.";
sem SituationRead.anonymized_summary = "A short third-person clause describing the HOUSEHOLD and its practical constraints only. Do NOT say what they need -- that is carried separately. Strip every name, street address, employer, full ZIP, phone number and anything else identifying. Under 15 words, ending in a period. e.g. 'Household of 3; no car, no stove access, no photo ID.'";
sem SituationRead.headline = "A short, warm, second-person sentence acknowledging what they are dealing with. Under 15 words. No platitudes, no 'I'm sorry to hear'.";

def read_situation(text: str) -> SituationRead by llm(temperature=0.2);
sem read_situation = "Read a person's plain-language description of an acute crisis and extract structured facts, plus a fully anonymized public summary of the need.";
sem read_situation.text = "What the person typed, verbatim.";


# ===========================================================================
# Role 2 - the privacy auditor (a second, adversarial pass)
# ===========================================================================

obj LeakAudit {
    has safe: bool;
    has leaks: list[str];
    has repaired_summary: str;
}

sem LeakAudit = "The result of auditing a supposedly-anonymized summary for anything that could identify a specific person.";
sem LeakAudit.safe = "True only if the summary contains nothing that could help identify the person: no names, street addresses, full ZIPs, phone numbers, employers, schools, or unusually specific details.";
sem LeakAudit.leaks = "Each specific fragment of the summary that leaks identity. Empty when safe.";
sem LeakAudit.repaired_summary = "The summary rewritten to remove every leak while keeping the practical household constraints that matter for matching (household size, no transport, no cooking facilities, missing documents). If already safe, return it unchanged.";

def audit_anonymization(original_text: str, proposed_summary: str) -> LeakAudit by llm(temperature=0.0);
sem audit_anonymization = "You are a privacy auditor. Given what a person originally wrote and a summary that is about to be published publicly to strangers, find anything in the summary that could identify them, and repair it. Be adversarial: assume the summary writer was careless.";
sem audit_anonymization.original_text = "What the person originally typed, which contains identifying details.";
sem audit_anonymization.proposed_summary = "The summary about to be shown publicly. Audit THIS, not the original.";


# ===========================================================================
# Role 3 - the clarifying question
# ===========================================================================

obj Clarification {
    has needed: bool;
    has question: str;
    has why: str;
}

sem Clarification = "A decision about whether one more fact is worth asking for before building a plan.";
sem Clarification.needed = "True only if a single missing fact would materially change which organisations this person should be sent to. False if the plan is already actionable -- someone in crisis should not be interrogated.";
sem Clarification.question = "The one question to ask, in plain warm second-person language, under 20 words. Empty when not needed.";
sem Clarification.why = "One short sentence explaining what the answer would change about the plan. Empty when not needed.";

def ask_clarifying(text: str, known_categories: str, known_assets: str) -> Clarification by llm(temperature=0.2);
sem ask_clarifying = "Decide whether asking exactly one more question would materially improve this person's plan. Default to NOT asking -- only ask when the answer would change which orgs they are routed to.";
sem ask_clarifying.text = "What the person said about their situation.";
sem ask_clarifying.known_categories = "Categories of help already identified, comma-separated.";
sem ask_clarifying.known_assets = "Documents and resources they already confirmed having, comma-separated.";


# ===========================================================================
# Role 4 - eligibility reasoning
# ===========================================================================

obj EligibilityVerdict {
    has satisfied: bool;
    has reasoning: str;
    has unblock_action: str;
}

sem EligibilityVerdict = "A judgement about whether one person clears one specific eligibility gate.";
sem EligibilityVerdict.satisfied = "True only if the person's stated situation clearly already satisfies the requirement. If it is unclear or unstated, answer False -- being told about a gate early is the whole point.";
sem EligibilityVerdict.reasoning = "One short sentence, addressed to the person, explaining why. Reference what they actually said.";
sem EligibilityVerdict.unblock_action = "If not satisfied: the single most concrete next action that would clear this gate, phrased as an instruction under 20 words. If satisfied: an empty string.";

def judge_requirement(
    situation: str,
    assets: str,
    requirement: str,
    requirement_kind: str,
    workaround: str
) -> EligibilityVerdict by llm(temperature=0.1);
sem judge_requirement = "Decide whether this person's situation satisfies this organisation's eligibility requirement, and if not, what single action would unblock them.";
sem judge_requirement.situation = "The person's own description of their circumstances.";
sem judge_requirement.assets = "Comma-separated list of documents and resources the person confirmed they have.";
sem judge_requirement.requirement = "The requirement the organisation enforces.";
sem judge_requirement.requirement_kind = "Category of the requirement: 'document', 'residency', 'income', or 'appointment'.";
sem judge_requirement.workaround = "The known way to satisfy this requirement, if the organisation publishes one.";


# ===========================================================================
# Role 5 - soft matching (a genuinely different kind of reasoning)
# ===========================================================================

obj MatchVerdict {
    has fits: bool;
    has score: int;
    has units: int;
    has rationale: str;
}

sem MatchVerdict = "A judgement about whether a specific donated pledge actually helps a specific anonymized need.";
sem MatchVerdict.fits = "True only if this pledge would genuinely help. A pledge that technically matches the category but is unusable by this household (e.g. food that needs cooking for someone with no stove) does NOT fit.";
sem MatchVerdict.score = "Fit quality from 0 to 100. 0 means useless, 100 means a perfect fit for this household's constraints.";
sem MatchVerdict.units = "How many units of the pledge to allocate to this need, given the household size. Never more than the remaining units available.";
sem MatchVerdict.rationale = "One sentence for the organisation's records explaining why this pairing works. Never mention or invent any identifying detail about the recipient.";

def judge_match(
    need_summary: str,
    need_category: str,
    household: int,
    pledge_kind: str,
    pledge_description: str,
    pledge_notes: str,
    remaining_units: int
) -> MatchVerdict by llm(temperature=0.3);
sem judge_match = "Decide whether a donor's pledge is a good fit for an anonymized community need, reasoning about practical usability rather than just matching categories.";
sem judge_match.need_summary = "The anonymized description of what is needed.";
sem judge_match.need_category = "One of 'food', 'shelter', 'legal', 'jobs'.";
sem judge_match.household = "Number of people the need covers.";
sem judge_match.pledge_kind = "What kind of thing was pledged: 'food', 'funds', 'goods', or 'time'.";
sem judge_match.pledge_description = "What the donor actually pledged, in their own words.";
sem judge_match.pledge_notes = "Any constraints the donor attached to the pledge.";
sem judge_match.remaining_units = "Units of this pledge still unallocated. Allocating more than this is invalid.";


# ===========================================================================
# Role 7 - escalation strategy  (role 6, the ReAct planner, is in core/agent.jac)
# ===========================================================================

obj EscalationPlan {
    has widen_radius: bool;
    has reword_as: str;
    has also_try_category: str;
    has reasoning: str;
}

sem EscalationPlan = "A decision about how to get an unanswered need answered, made after it has already sat unfilled.";
sem EscalationPlan.widen_radius = "True if the need should be broadcast to a wider ring of organisations than it currently reaches.";
sem EscalationPlan.reword_as = "The anonymized summary rewritten to be more likely to attract a match -- leading with the most actionable constraint. Must stay anonymous and under 20 words. Empty to keep the current wording.";
sem EscalationPlan.also_try_category = "A second category of help that would relieve the same underlying problem, if one genuinely would. One of 'food', 'shelter', 'legal', 'jobs', or empty. E.g. an unanswered shelter need may be relieved by legal help that stops the eviction.";
sem EscalationPlan.reasoning = "One sentence for the org's records on why this escalation is the right move now.";

def escalation_strategy(
    summary: str,
    category: str,
    urgency: str,
    hours_open: int,
    prior_escalations: int,
    orgs_already_reached: str
) -> EscalationPlan by llm(temperature=0.3);
sem escalation_strategy = "A community need has gone unanswered. Decide how to escalate it: widen the broadcast, reword the ask, and/or open a second front in a different category. Escalate harder the longer it has sat and the more times it has already been escalated.";
sem escalation_strategy.summary = "The current anonymized summary of the need.";
sem escalation_strategy.category = "The category of help currently being asked for.";
sem escalation_strategy.urgency = "Current urgency level.";
sem escalation_strategy.hours_open = "How many hours this need has been open with no match.";
sem escalation_strategy.prior_escalations = "How many times this need has already been escalated.";
sem escalation_strategy.orgs_already_reached = "Names of organisations already reached, comma-separated.";


# ===========================================================================
# Role 8 - plan narration
# ===========================================================================

def next_step_nudge(resolved: str, next_open_step: str) -> str by llm(temperature=0.5, max_tokens=120);
sem next_step_nudge = "Write the one-line update a person in crisis sees when part of their plan just got resolved for them. Lead with the good news, then point at exactly one next thing. Warm, plain, under 25 words. No exclamation marks, no 'amazing', no emoji.";
sem next_step_nudge.resolved = "What just got covered for them.";
sem next_step_nudge.next_open_step = "The title of the next still-open step in their plan, or an empty string if nothing is left.";


# ===========================================================================
# Deterministic fallbacks
# ===========================================================================
#
# These are a LAST RESORT, not a peer of the model. Every one of them runs only
# after `_fallback_used()` has logged that the model is not answering, and under
# BRIDGE_STRICT_LLM they never run at all. They exist so a dead key at 3:59pm
# does not take the whole demo down with it.

glob _CANON: list[str] = ["food", "shelter", "legal", "jobs"];

glob _CATEGORY_WORDS: dict[str, list[str]] = {
    "food": [
        "food", "eat", "eating", "groceries", "grocery", "hungry", "hunger",
        "meal", "meals", "pantry", "snap", "ebt", "formula", "fed", "feed"
    ],
    "shelter": [
        "evict", "eviction", "evicted", "rent", "homeless", "shelter",
        "housing", "sleep", "sleeping", "landlord", "apartment", "motel",
        "couch", "utilities", "electricity", "heat",
        # "car" alone is a constraint ("no car"), not a housing signal -- only
        # living in one is. Matching bare "car" used to rank a food emergency as
        # shelter-first.
        "in my car", "in the car", "living in my car", "sleeping in my car"
    ],
    "legal": [
        "legal", "lawyer", "attorney", "court", "hearing", "notice", "sued",
        "custody", "immigration", "ice", "warrant", "ticket", "record",
        "expunge", "evict", "eviction", "landlord"
    ],
    "jobs": [
        "job", "jobs", "work", "employment", "unemployed", "laid off",
        "fired", "hire", "hiring", "resume", "interview", "income", "paycheck"
    ]
};

glob _ASSET_WORDS: dict[str, list[str]] = {
    "state photo ID": ["photo id", "state id", "drivers license", "driver's license", "id card"],
    "proof of address": ["proof of address", "lease", "utility bill", "mail"],
    "social security card": ["social security", "ssn", "ss card"],
    "car": ["car", "vehicle", "truck", "drive"],
    "phone": ["phone", "cell", "mobile"],
    "bank account": ["bank account", "checking", "direct deposit"]
};

glob _CRITICAL_WORDS: list[str] = [
    "today", "tonight", "tomorrow", "right now", "nothing to eat",
    "no food", "out of food", "evicted", "on the street", "emergency"
];

glob _HIGH_WORDS: list[str] = [
    "this week", "few days", "eviction notice", "shut off", "running out",
    "almost out", "behind on"
];

glob _NEGATIONS: list[str] = ["no ", "not ", "don't", "dont", "without", "lost my", "lost the", "never had"];

glob _CATEGORY_LABEL: dict[str, str] = {
    "food": "groceries",
    "shelter": "a safe place to stay",
    "legal": "legal help",
    "jobs": "work"
};


def _mentions(text: str, phrase: str) -> bool {
    return phrase in text;
}


"""True when the phrase shows up right after a negation -- 'no photo ID'."""
def _negated_near(text: str, phrase: str) -> bool {
    idx = text.find(phrase);
    while idx != -1 {
        window = text[max(0, idx - 22):idx];
        for neg in _NEGATIONS {
            if neg in window {
                return True;
            }
        }
        idx = text.find(phrase, idx + 1);
    }
    return False;
}


def _canon_rank(cat: str) -> int {
    return _CANON.index(cat) if cat in _CANON else len(_CANON);
}


def heuristic_read(text: str) -> SituationRead {
    low = text.lower();

    scored: list[list] = [];
    for (cat, words) in _CATEGORY_WORDS.items() {
        hits = len([w for w in words if _mentions(low, w)]);
        if hits > 0 {
            scored.append([hits, cat]);
        }
    }
    # Most hits first, ties broken by canonical need order (food, shelter,
    # legal, jobs). The old `sort(reverse=True)` broke ties reverse-
    # alphabetically, which ranked "shelter" above "food" on an equal score and
    # greeted a food emergency with "let's get you a safe place to stay".
    scored.sort(key=lambda (row: list) -> list {
        return [-(row[0] as int), _canon_rank(row[1] as str)];
    });
    categories = [row[1] as str for row in scored];
    if not categories {
        categories = ["food"];
    }

    household = 1;
    kids = re.search(r"(\d+)\s*(kids|children|kid|child)", low);
    words_to_n = {"two": 2, "three": 3, "four": 4, "five": 5, "six": 6};
    if kids {
        household = int(kids.group(1)) + 1;
    } else {
        for (word, n) in words_to_n.items() {
            if re.search(word + r"\s*(kids|children|kid|child)", low) {
                household = n + 1;
            }
        }
    }
    people = re.search(r"(?:family of|household of)\s*(\d+)", low);
    if people {
        household = int(people.group(1));
    }

    zip_prefix = "";
    zm = re.search(r"\b(\d{3})\d{0,2}x*\b", low);
    if zm {
        zip_prefix = zm.group(1);
    }

    assets: list[str] = [];
    for (asset, phrases) in _ASSET_WORDS.items() {
        for phrase in phrases {
            if _mentions(low, phrase) and not _negated_near(low, phrase) {
                assets.append(asset);
                break;
            }
        }
    }

    urgency = "medium";
    for word in _HIGH_WORDS {
        if word in low { urgency = "high"; }
    }
    for word in _CRITICAL_WORDS {
        if word in low { urgency = "critical"; }
    }

    wants = " and ".join([_CATEGORY_LABEL.get(c, c) for c in categories[:2]]);
    who = "Household of " + str(household) if household > 1 else "One adult";
    limits: list[str] = [];
    if "no car" in low or "without a car" in low or "no vehicle" in low {
        limits.append("no transport");
    }
    if "no stove" in low or "no kitchen" in low or "can't cook" in low or "no way to cook" in low {
        limits.append("no way to cook");
    }
    if "no id" in low or "no photo id" in low or "lost my id" in low {
        limits.append("no photo ID");
    }
    tail = "; " + ", ".join(limits) if limits else "";
    summary = f"{who}{tail}.";

    return SituationRead(
        categories=categories,
        urgency=urgency,
        household=household,
        zip_prefix=zip_prefix,
        assets=assets,
        anonymized_summary=summary,
        headline=f"Let's get you {wants}. Here is the fastest path from where you are."
    );
}


glob _LEAK_PATTERNS: list[list[str]] = [
    ["phone number", r"\b\d{3}[-.\s]?\d{3}[-.\s]?\d{4}\b"],
    ["full ZIP", r"\b\d{5}\b"],
    ["street address", r"\b\d{2,6}\s+[A-Z][a-z]+\s+(St|Street|Ave|Avenue|Rd|Road|Blvd|Way|Dr|Drive)\b"],
    ["email address", r"\b[\w.]+@[\w.]+\b"]
];


def heuristic_audit(original_text: str, proposed_summary: str) -> LeakAudit {
    leaks: list[str] = [];
    repaired = proposed_summary;
    for pair in _LEAK_PATTERNS {
        hit = re.search(pair[1], repaired);
        if hit {
            leaks.append(f"{pair[0]}: {hit.group(0)}");
            repaired = repaired.replace(hit.group(0), "[redacted]");
        }
    }
    # Any capitalised word from the original that survived into the summary and
    # is not a known constraint word is treated as a possible name.
    safe_words = [
        "Household", "One", "No", "Needs", "Family", "Adult", "Adults",
        "Children", "Child", "Kids"
    ];
    for token in re.findall(r"\b[A-Z][a-z]{2,}\b", proposed_summary) {
        if token not in safe_words and token in original_text {
            leaks.append(f"possible name: {token}");
            repaired = repaired.replace(token, "[redacted]");
        }
    }
    return LeakAudit(safe=not leaks, leaks=leaks, repaired_summary=repaired);
}


def heuristic_clarify(text: str, known_categories: str, known_assets: str) -> Clarification {
    low = text.lower();
    if "food" in known_categories and "no way to cook" not in low and "stove" not in low {
        return Clarification(
            needed=True,
            question="Do you have a working stove and fridge where you're staying?",
            why="It decides whether to send fresh groceries or ready-to-eat meals."
        );
    }
    if not known_assets or known_assets == "nothing confirmed" {
        return Clarification(
            needed=True,
            question="Do you have a photo ID on you right now?",
            why="Most food banks turn people away at the door without one."
        );
    }
    return Clarification(needed=False, question="", why="");
}


def heuristic_requirement(
    situation: str,
    assets: str,
    requirement: str,
    requirement_kind: str,
    workaround: str
) -> EligibilityVerdict {
    low = situation.lower();
    have = assets.lower();
    req = requirement.lower();

    if requirement_kind == "income" {
        return EligibilityVerdict(
            satisfied=True,
            reasoning="This one is self-attested -- you state your income, no paperwork up front.",
            unblock_action=""
        );
    }

    if requirement_kind == "residency" {
        return EligibilityVerdict(
            satisfied=True,
            reasoning="You are inside their service area, so residency is covered.",
            unblock_action=""
        );
    }

    if requirement_kind == "appointment" {
        return EligibilityVerdict(
            satisfied=False,
            reasoning="They only take people who have booked ahead -- walk-ins get turned away.",
            unblock_action=workaround if workaround else "Call ahead and book the earliest slot they have."
        );
    }

    # document
    stop = ["with", "that", "they", "your", "this", "from", "have", "must", "under", "each", "will", "when", "issued"];
    req_tokens = [t for t in re.split(r"[^a-z]+", req) if len(t) > 3 and t not in stop];
    have_tokens = [t for t in re.split(r"[^a-z]+", have) if t];
    overlap = len([t for t in req_tokens if t in have_tokens]);
    if req_tokens and overlap >= max(1, len(req_tokens) // 2) and not _negated_near(low, req) {
        return EligibilityVerdict(
            satisfied=True,
            reasoning=f"You already said you have this, so \"{requirement}\" is not a blocker.",
            unblock_action=""
        );
    }
    return EligibilityVerdict(
        satisfied=False,
        reasoning=f"They ask for \"{requirement}\" at the door, and you have not said you have it.",
        unblock_action=workaround if workaround else f"Get \"{requirement}\" before you go -- otherwise you will be turned away."
    );
}


glob _KIND_FIT: dict[str, list[str]] = {
    "food": ["food", "funds", "goods"],
    "shelter": ["funds", "goods", "time"],
    "legal": ["time", "funds"],
    "jobs": ["time", "goods", "funds"]
};

glob _UNUSABLE: dict[str, list[str]] = {
    "no way to cook": ["dry", "raw", "uncooked", "rice", "beans", "pasta", "flour", "requires cooking", "stove"],
    "no transport": ["pickup only", "pick up only", "collect from"]
};


def heuristic_match(
    need_summary: str,
    need_category: str,
    household: int,
    pledge_kind: str,
    pledge_description: str,
    pledge_notes: str,
    remaining_units: int
) -> MatchVerdict {
    if remaining_units <= 0 {
        return MatchVerdict(fits=False, score=0, units=0, rationale="Pledge is fully allocated.");
    }

    allowed = _KIND_FIT.get(need_category, []) as list[str];
    if pledge_kind not in allowed {
        return MatchVerdict(
            fits=False,
            score=5,
            units=0,
            rationale=f"A {pledge_kind} pledge does not address a {need_category} need."
        );
    }

    summary = need_summary.lower();
    blob = (pledge_description + " " + pledge_notes).lower();

    score = 55;
    if pledge_kind == need_category { score += 20; }

    # the interesting bit: usability against the household's stated constraints
    blocked = "";
    for (constraint, words) in _UNUSABLE.items() {
        if constraint in summary {
            for w in words {
                if w in blob {
                    blocked = constraint;
                }
            }
        }
    }
    if blocked {
        return MatchVerdict(
            fits=False,
            score=15,
            units=0,
            rationale=f"Technically the right category, but unusable for this household ({blocked})."
        );
    }

    if "ready to eat" in blob or "ready-to-eat" in blob or "prepared" in blob or "no cooking" in blob {
        if "no way to cook" in summary { score += 25; }
    }
    if "delivery" in blob or "deliver" in blob {
        if "no transport" in summary { score += 15; }
    }

    units = min(remaining_units, max(1, household));
    score = min(score, 97);
    return MatchVerdict(
        fits=True,
        score=score,
        units=units,
        rationale=f"{pledge_description} covers a household of {household} in this category, with {remaining_units} units on hand."
    );
}


def heuristic_escalation(
    summary: str,
    category: str,
    urgency: str,
    hours_open: int,
    prior_escalations: int,
    orgs_already_reached: str
) -> EscalationPlan {
    _ = (summary, urgency, orgs_already_reached);
    second = "";
    if category == "shelter" and prior_escalations >= 1 {
        second = "legal";
    } elif category == "food" and prior_escalations >= 2 {
        second = "jobs";
    }
    return EscalationPlan(
        widen_radius=True,
        reword_as="",
        also_try_category=second,
        reasoning=f"Unanswered for {hours_open}h after {prior_escalations} escalation(s) -- widening the radius."
    );
}


def heuristic_nudge(resolved: str, next_open_step: str) -> str {
    if next_open_step {
        return f"Good news -- {resolved} is covered. Next up: {next_open_step}.";
    }
    return f"Good news -- {resolved} is covered. Nothing else is blocking you right now.";
}


# ===========================================================================
# Safe wrappers -- the ONLY entry points walkers should call
# ===========================================================================

def read_situation_safe(text: str) -> SituationRead {
    if live() {
        try {
            _note("read_situation");
            return read_situation(text);
        } except Exception as e {
            _degrade("read_situation", str(e));
        }
    }
    _fallback_used("read_situation");
    return heuristic_read(text);
}


def audit_anonymization_safe(original_text: str, proposed_summary: str) -> LeakAudit {
    if live() {
        try {
            _note("audit_anonymization");
            return audit_anonymization(original_text, proposed_summary);
        } except Exception as e {
            _degrade("audit_anonymization", str(e));
        }
    }
    _fallback_used("audit_anonymization");
    return heuristic_audit(original_text, proposed_summary);
}


def ask_clarifying_safe(text: str, known_categories: str, known_assets: str) -> Clarification {
    if live() {
        try {
            _note("ask_clarifying");
            return ask_clarifying(text, known_categories, known_assets);
        } except Exception as e {
            _degrade("ask_clarifying", str(e));
        }
    }
    _fallback_used("ask_clarifying");
    return heuristic_clarify(text, known_categories, known_assets);
}


def judge_requirement_safe(
    situation: str,
    assets: str,
    requirement: str,
    requirement_kind: str,
    workaround: str
) -> EligibilityVerdict {
    if live() {
        try {
            _note("judge_requirement");
            return judge_requirement(situation, assets, requirement, requirement_kind, workaround);
        } except Exception as e {
            _degrade("judge_requirement", str(e));
        }
    }
    _fallback_used("judge_requirement");
    return heuristic_requirement(situation, assets, requirement, requirement_kind, workaround);
}


def judge_match_safe(
    need_summary: str,
    need_category: str,
    household: int,
    pledge_kind: str,
    pledge_description: str,
    pledge_notes: str,
    remaining_units: int
) -> MatchVerdict {
    if live() {
        try {
            _note("judge_match");
            verdict = judge_match(
                need_summary, need_category, household,
                pledge_kind, pledge_description, pledge_notes, remaining_units
            );
            verdict.units = max(0, min(verdict.units, remaining_units));
            return verdict;
        } except Exception as e {
            _degrade("judge_match", str(e));
        }
    }
    _fallback_used("judge_match");
    return heuristic_match(
        need_summary, need_category, household,
        pledge_kind, pledge_description, pledge_notes, remaining_units
    );
}


def escalation_strategy_safe(
    summary: str,
    category: str,
    urgency: str,
    hours_open: int,
    prior_escalations: int,
    orgs_already_reached: str
) -> EscalationPlan {
    if live() {
        try {
            _note("escalation_strategy");
            return escalation_strategy(
                summary, category, urgency, hours_open,
                prior_escalations, orgs_already_reached
            );
        } except Exception as e {
            _degrade("escalation_strategy", str(e));
        }
    }
    _fallback_used("escalation_strategy");
    return heuristic_escalation(
        summary, category, urgency, hours_open, prior_escalations, orgs_already_reached
    );
}


def next_step_nudge_safe(resolved: str, next_open_step: str) -> str {
    if live() {
        try {
            _note("next_step_nudge");
            return next_step_nudge(resolved, next_open_step);
        } except Exception as e {
            _degrade("next_step_nudge", str(e));
        }
    }
    _fallback_used("next_step_nudge");
    return heuristic_nudge(resolved, next_open_step);
}


# ---------------------------------------------------------------------------
# Parallel launchers
# ---------------------------------------------------------------------------
#
# The judgements below are independent of each other, so walkers launch them
# all at once on the thread pool and collect afterwards -- with a real model
# that turns N sequential round trips into one.
#
# These one-line wrappers are NOT ceremony. Writing `flow judge_x(g.label, ...)`
# directly inside a comprehension captures the loop variable by REFERENCE, so
# every future ends up reading the last item (verified: 5 futures, 5 copies of
# the last verdict, deterministically). Going through a function call gives each
# future its own parameter binding. Do not inline these.

def launch_requirement(
    situation: str,
    assets: str,
    requirement: str,
    requirement_kind: str,
    workaround: str
) -> any {
    return flow judge_requirement_safe(situation, assets, requirement, requirement_kind, workaround);
}


def launch_match(
    need_summary: str,
    need_category: str,
    household: int,
    pledge_kind: str,
    pledge_description: str,
    pledge_notes: str,
    remaining_units: int
) -> any {
    return flow judge_match_safe(
        need_summary, need_category, household,
        pledge_kind, pledge_description, pledge_notes, remaining_units
    );
}
