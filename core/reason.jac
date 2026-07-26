"""Bridge - the reasoning layer.

Every judgement Bridge makes about a human being is made by the model. There is
no keyword table, no regex, no substitute answer anywhere in this file. There
are **seven distinct LLM roles**, deliberately not one prompt reused seven
times:

  1. `read_situation`      -- free text -> structured facts + an anonymized
                              one-liner. The anonymization is a reasoning step.
  2. `audit_anonymization` -- a SECOND model pass that tries to find identity
                              leaks in role 1's output before it is published to
                              the commons. The privacy claim is enforced, not
                              asserted.
  3. `judge_requirement`   -- does this person's situation clear this org's
                              specific eligibility gate, and if not, what single
                              action unblocks it.
  4. `judge_match`         -- soft-matches a live need against a donor pledge on
                              *fit*, not category equality.
  5. `plan_strategy`       -- the ReAct caseworker. Lives in `core/agent.jac`
                              because its tools traverse the graph.
  6. `escalation_strategy` -- when a need goes unanswered, reasons about *how*
                              to widen the ask, not just how far.
  7. `next_step_nudge`     -- the one line the person actually reads when their
                              plan changes underneath them.

## Engine honesty

`ensure_engine()` makes one real structured `by llm()` call at boot and only
reports `llm` if the model round-trips a typed object successfully. Every call
site is guarded by `require_engine()`, which **raises** the moment the engine
is not configured -- there is no code path in which a missing key produces an
answer. If a role's own call fails after that (a bad key, a rate limit, a
network blip), the real provider error is recorded and re-raised verbatim; it
is never swallowed and never replaced with a guess.

A single failed call does NOT permanently downgrade the engine. `ENGINE.mode`
is decided once, at the boot-time preflight, from whether a working model
connection exists at all; a later transient failure updates `ENGINE.reason` and
`ENGINE.failures` for display and is re-raised for that one caller, but the
next request tries the real model again. Conflating "one call failed" with "the
model is gone" used to mean a single rate-limit blip could brick every feature
until the process restarted -- that bug is fixed here.
"""

import os;
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

"""Marker prefix on every error raised for a missing/broken engine.

Client code matches on this exact string to tell "the model is not configured"
apart from an ordinary transient failure, without parsing prose.
"""
glob ENGINE_UNAVAILABLE_TAG: str = "ENGINE_UNAVAILABLE";


def has_key -> bool {
    for var in _KEY_VARS {
        if os.environ.get(var) {
            return True;
        }
    }
    return False;
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
    print(f"[bridge] {line}");
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


"""Record that ONE call to `role` failed, without downgrading the whole engine.

`ENGINE.mode` is not touched here -- see the module docstring. This only updates
the counters and the display reason, then the caller re-raises.
"""
def _note_failure(role: str, err: str) {
    ENGINE.failures += 1;
    ENGINE.reason = _short(err);
    _push_degrade(role, ENGINE.reason);
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
eight real roles will also parse, not just that a socket opened. Runs once per
process; call `ensure_engine()` freely, it is idempotent after the first check.
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


"""Refuse to proceed unless there is a real, working model connection.

Every `_safe` wrapper in this file calls this FIRST, before anything else runs
-- so a missing key fails immediately and loudly, before any graph mutation,
rather than partway through one. There is no fallback path after this raises.
"""
def require_engine(role: str) {
    if not live() {
        why = ENGINE.reason if ENGINE.reason else "no model API key configured";
        raise RuntimeError(
            f"{ENGINE_UNAVAILABLE_TAG}: Bridge has no working model connection ({why}). "
            "Set OPENAI_API_KEY (or ANTHROPIC_API_KEY / GOOGLE_API_KEY) and restart the "
            f"server. '{role}' only ever answers from the model -- there is no fallback."
        );
    }
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
sem SituationRead.categories = "Which kinds of help this person needs. Use only these exact values: 'food', 'shelter', 'legal', 'jobs'. Order by urgency, most urgent first. Only include a category they actually need -- mentioning they have no car is a constraint, not a request for shelter. If they identify as a senior/elderly/retired person seeking help but do not name a concrete need, include 'food' (senior meals / congregate dining is the usual first resource) and any other category their words clearly imply.";
sem SituationRead.urgency = "How fast this must be solved. Exactly one of: 'critical' (today/tonight), 'high' (this week), 'medium' (this month), 'low'.";
sem SituationRead.household = "How many people are being fed or housed, including the person themself. Default to 1 if not stated.";
sem SituationRead.zip_prefix = "The first 3 digits of their ZIP code if mentioned, otherwise an empty string. Never the full ZIP.";
sem SituationRead.assets = "Concrete things they say they HAVE that could satisfy an eligibility requirement: e.g. 'state photo ID', 'proof of address', 'social security card', 'car', 'phone', 'bank account'. Also include audience facts they claim about themselves when relevant to program eligibility: e.g. 'senior', 'veteran', 'family with children'. Only list what they actually claim. Never list something they say they lack.";
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
# Role 3 - eligibility reasoning
# ===========================================================================

obj EligibilityVerdict {
    has satisfied: bool;
    has reasoning: str;
    has unblock_action: str;
}

sem EligibilityVerdict = "A judgement about whether one person clears one specific eligibility gate.";
sem EligibilityVerdict.satisfied = "True only if the person's stated situation clearly already satisfies the requirement. If it is unclear or unstated, answer False -- being told about a gate early is the whole point.";
sem EligibilityVerdict.reasoning = "One short sentence, addressed to the person, explaining why they do or do not qualify. Reference what they actually said.";
sem EligibilityVerdict.unblock_action = "If not satisfied: the simplest concrete steps to qualify, under 30 words, using the published workaround when given. Example: 'Ask the shelter front desk for a signed letter, or bring any mail with your name on it.' If satisfied: an empty string.";

def judge_requirement(
    situation: str,
    assets: str,
    requirement: str,
    requirement_kind: str,
    workaround: str
) -> EligibilityVerdict by llm(temperature=0.1);
sem judge_requirement = "Decide whether this person already qualifies for this organisation's requirement. If not, tell them the specific simple steps to qualify (how to get a shelter letter, free ID, etc.) using the published workaround. Never leave them with only the requirement name.";
sem judge_requirement.situation = "The person's own description of their circumstances.";
sem judge_requirement.assets = "Comma-separated list of documents and resources the person confirmed they have.";
sem judge_requirement.requirement = "The requirement the organisation enforces.";
sem judge_requirement.requirement_kind = "Category of the requirement: 'document', 'residency', 'income', or 'appointment'.";
sem judge_requirement.workaround = "The known way to satisfy this requirement, if the organisation publishes one. Prefer this wording when writing unblock_action.";


# ===========================================================================
# Role 4 - soft matching (a genuinely different kind of reasoning)
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
# Role 6 - escalation strategy  (role 5, the ReAct planner, is in core/agent.jac)
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
# Role 7 - plan narration
# ===========================================================================

def next_step_nudge(resolved: str, next_open_step: str) -> str by llm(temperature=0.5, max_tokens=120);
sem next_step_nudge = "Write the one-line update a person in crisis sees when part of their plan just got resolved for them. Lead with the good news, then point at exactly one next thing. Warm, plain, under 25 words. No exclamation marks, no 'amazing', no emoji.";
sem next_step_nudge.resolved = "What just got covered for them.";
sem next_step_nudge.next_open_step = "The title of the next still-open step in their plan, or an empty string if nothing is left.";


# ===========================================================================
# Role 9 - helper offer intake
# ===========================================================================

obj HelperOfferItem {
    has name: str;
    has kind: str;
    has description: str;
    has details: list[str];
    has notes: str = "";
}

sem HelperOfferItem = "One concrete service or good a volunteer can offer.";
sem HelperOfferItem.name = "Short title for the offer, e.g. 'Meal cooking and delivery'. Under 6 words.";
sem HelperOfferItem.kind = "Exactly one of: 'food', 'goods', 'funds', 'time'.";
sem HelperOfferItem.description = "One plain sentence of what they are offering.";
sem HelperOfferItem.details = "2-4 short bullet lines of specifics from what they said (radius, schedule, quantity, constraints).";
sem HelperOfferItem.notes = "Constraints only (distance, days, dietary limits). Empty if none.";

obj HelperOfferRead {
    has offers: list[HelperOfferItem];
    has reply: str;
}

sem HelperOfferRead = "Structured offers extracted from a volunteer's description of how they can help.";
sem HelperOfferRead.offers = "Every distinct help they offered. Empty if they did not offer anything concrete.";
sem HelperOfferRead.reply = "One warm sentence acknowledging what they offered, under 20 words. No emoji.";

def read_helper_offers(text: str) -> HelperOfferRead by llm(temperature=0.2);
sem read_helper_offers = "Read what a volunteer says they can do and extract concrete offered services or goods. Split combined offers into separate items when they are different kinds of help.";
sem read_helper_offers.text = "What the volunteer typed, verbatim.";


# ===========================================================================
# Safe wrappers -- the ONLY entry points walkers should call
# ===========================================================================
#
# Every one of these: (1) requires a live engine or raises immediately, (2) on
# a real call failure, records it for the UI and re-raises the actual provider
# error verbatim. Nothing here ever returns a substitute answer.

def read_situation_safe(text: str) -> SituationRead {
    require_engine("read_situation");
    try {
        _note("read_situation");
        return read_situation(text);
    } except Exception as e {
        _note_failure("read_situation", str(e));
        raise;
    }
}


def audit_anonymization_safe(original_text: str, proposed_summary: str) -> LeakAudit {
    require_engine("audit_anonymization");
    try {
        _note("audit_anonymization");
        return audit_anonymization(original_text, proposed_summary);
    } except Exception as e {
        _note_failure("audit_anonymization", str(e));
        raise;
    }
}




def judge_requirement_safe(
    situation: str,
    assets: str,
    requirement: str,
    requirement_kind: str,
    workaround: str
) -> EligibilityVerdict {
    require_engine("judge_requirement");
    try {
        _note("judge_requirement");
        return judge_requirement(situation, assets, requirement, requirement_kind, workaround);
    } except Exception as e {
        _note_failure("judge_requirement", str(e));
        raise;
    }
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
    require_engine("judge_match");
    try {
        _note("judge_match");
        verdict = judge_match(
            need_summary, need_category, household,
            pledge_kind, pledge_description, pledge_notes, remaining_units
        );
        verdict.units = max(0, min(verdict.units, remaining_units));
        return verdict;
    } except Exception as e {
        _note_failure("judge_match", str(e));
        raise;
    }
}


def escalation_strategy_safe(
    summary: str,
    category: str,
    urgency: str,
    hours_open: int,
    prior_escalations: int,
    orgs_already_reached: str
) -> EscalationPlan {
    require_engine("escalation_strategy");
    try {
        _note("escalation_strategy");
        return escalation_strategy(
            summary, category, urgency, hours_open,
            prior_escalations, orgs_already_reached
        );
    } except Exception as e {
        _note_failure("escalation_strategy", str(e));
        raise;
    }
}


def next_step_nudge_safe(resolved: str, next_open_step: str) -> str {
    require_engine("next_step_nudge");
    try {
        _note("next_step_nudge");
        return next_step_nudge(resolved, next_open_step);
    } except Exception as e {
        _note_failure("next_step_nudge", str(e));
        raise;
    }
}


def read_helper_offers_safe(text: str) -> HelperOfferRead {
    require_engine("read_helper_offers");
    try {
        _note("read_helper_offers");
        return read_helper_offers(text);
    } except Exception as e {
        _note_failure("read_helper_offers", str(e));
        raise;
    }
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
