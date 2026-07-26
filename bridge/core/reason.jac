"""Bridge - the reasoning layer.

Three *distinct* LLM roles, deliberately not one prompt reused three times:

  1. `read_situation`     -- turns free text into structured facts AND strips it
                             down to an anonymized one-liner. The anonymization
                             itself is a reasoning step, not a regex.
  2. `judge_requirement`  -- decides whether a specific person's specific
                             situation satisfies one org's specific eligibility
                             gate, and if not, what unblocks it.
  3. `judge_match`        -- soft-matches a live need against a donor pledge on
                             *fit*, not category equality ("shelf-stable staples"
                             vs "family of 5, no stove access").
  4. `next_step_nudge`    -- writes the one line the person actually reads when
                             their plan changes underneath them.

Every one of them is paired with a deterministic fallback. If no model is
configured -- or the model errors mid-demo -- Bridge degrades to heuristics and
keeps running instead of dying on stage. `engine()` reports which one is live.
"""

import os;
import re;


# ---------------------------------------------------------------------------
# Engine availability
# ---------------------------------------------------------------------------

glob _KEY_VARS: list[str] = [
    "OPENAI_API_KEY",
    "ANTHROPIC_API_KEY",
    "GOOGLE_API_KEY",
    "GEMINI_API_KEY",
    "OLLAMA_HOST"
];

glob LLM_ONLINE: bool = False;


def detect_llm -> bool {
    for var in _KEY_VARS {
        if os.environ.get(var) {
            return True;
        }
    }
    return False;
}


def engine -> str {
    return "llm" if LLM_ONLINE else "heuristic";
}


def _degrade(where: str, err: str) {
    LLM_ONLINE = False;
    print(f"[bridge] llm call failed in {where} ({err}) -- falling back to heuristics");
}


with entry {
    LLM_ONLINE = detect_llm();
}


# ---------------------------------------------------------------------------
# Role 1 - situation intake + anonymization
# ---------------------------------------------------------------------------

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
sem SituationRead.categories = "Which kinds of help this person needs. Use only these exact values: 'food', 'shelter', 'legal', 'jobs'. Order by urgency, most urgent first.";
sem SituationRead.urgency = "How fast this must be solved. Exactly one of: 'critical' (today/tonight), 'high' (this week), 'medium' (this month), 'low'.";
sem SituationRead.household = "How many people are being fed or housed, including the person themself. Default to 1 if not stated.";
sem SituationRead.zip_prefix = "The first 3 digits of their ZIP code if mentioned, otherwise an empty string. Never the full ZIP.";
sem SituationRead.assets = "Concrete things they say they HAVE that could satisfy an eligibility requirement: e.g. 'state photo ID', 'proof of address', 'social security card', 'car', 'phone', 'bank account'. Only list what they actually claim to have. Never list something they say they lack.";
sem SituationRead.anonymized_summary = "A short third-person clause describing the HOUSEHOLD and its practical constraints only. Do NOT say what they need -- that is carried separately. Strip every name, street address, employer, full ZIP, phone number and anything else identifying. Under 15 words, ending in a period. e.g. 'Household of 3; no car, no stove access, no photo ID.'";
sem SituationRead.headline = "A short, warm, second-person sentence acknowledging what they are dealing with. Under 15 words. No platitudes, no 'I'm sorry to hear'.";

def read_situation(text: str) -> SituationRead by llm(temperature=0.2);
sem read_situation = "Read a person's plain-language description of an acute crisis and extract structured facts, plus a fully anonymized public summary of the need.";
sem read_situation.text = "What the person typed, verbatim.";


# ---------------------------------------------------------------------------
# Role 2 - eligibility reasoning
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# Role 3 - soft matching (a genuinely different kind of reasoning)
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# Role 4 - plan narration
# ---------------------------------------------------------------------------

def next_step_nudge(resolved: str, next_open_step: str) -> str by llm(temperature=0.5, max_tokens=120);
sem next_step_nudge = "Write the one-line update a person in crisis sees when part of their plan just got resolved for them. Lead with the good news, then point at exactly one next thing. Warm, plain, under 25 words. No exclamation marks, no 'amazing', no emoji.";
sem next_step_nudge.resolved = "What just got covered for them.";
sem next_step_nudge.next_open_step = "The title of the next still-open step in their plan, or an empty string if nothing is left.";


# ===========================================================================
# Deterministic fallbacks -- these keep the demo alive with zero API keys
# ===========================================================================

glob _CATEGORY_WORDS: dict[str, list[str]] = {
    "food": [
        "food", "eat", "eating", "groceries", "grocery", "hungry", "hunger",
        "meal", "meals", "pantry", "snap", "ebt", "formula", "fed", "feed"
    ],
    "shelter": [
        "evict", "eviction", "evicted", "rent", "homeless", "shelter",
        "housing", "sleep", "sleeping", "landlord", "apartment", "motel",
        "couch", "car", "utilities", "electricity", "heat"
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


def heuristic_read(text: str) -> SituationRead {
    low = text.lower();

    scored: list[list] = [];
    for (cat, words) in _CATEGORY_WORDS.items() {
        hits = len([w for w in words if _mentions(low, w)]);
        if hits > 0 {
            scored.append([hits, cat]);
        }
    }
    scored.sort(reverse=True);
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
    if LLM_ONLINE {
        try {
            return read_situation(text);
        } except Exception as e {
            _degrade("read_situation", str(e));
        }
    }
    return heuristic_read(text);
}


def judge_requirement_safe(
    situation: str,
    assets: str,
    requirement: str,
    requirement_kind: str,
    workaround: str
) -> EligibilityVerdict {
    if LLM_ONLINE {
        try {
            return judge_requirement(situation, assets, requirement, requirement_kind, workaround);
        } except Exception as e {
            _degrade("judge_requirement", str(e));
        }
    }
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
    if LLM_ONLINE {
        try {
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
    return heuristic_match(
        need_summary, need_category, household,
        pledge_kind, pledge_description, pledge_notes, remaining_units
    );
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


def next_step_nudge_safe(resolved: str, next_open_step: str) -> str {
    if LLM_ONLINE {
        try {
            return next_step_nudge(resolved, next_open_step);
        } except Exception as e {
            _degrade("next_step_nudge", str(e));
        }
    }
    return heuristic_nudge(resolved, next_open_step);
}
