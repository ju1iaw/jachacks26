"""Bridge - the walkers.

Eight walkers, distinct jobs. Where one starts another it is because a graph
event demands it, never because a human clicked; otherwise they coordinate
purely by reading and writing the same graph:

    IntakeWalker          person's words  ->  Person node. Runs the intake read,
      |                   then a second adversarial pass that audits the
      |                   anonymization before anything reaches the commons.
      |
      +-- EligibilityPathWalker   Root -> Org -> Requirement, reasons at each
      |                           gate, writes a PlanStep per org (blocked ones
      |                           get an unblock step in front of them)
      |
      +-- NeedBroadcastWalker     turns every still-unmet category into an
      |                           anonymized Need on the commons, wires it to
      |                           nearby orgs, and wakes the matcher on it. The
      |                           topology IS the message.
      |
      +-- StrategyWalker          hands the situation to a ReAct agent holding
                                  four graph-reading tools and stores both the
                                  strategy it returns and the research path it
                                  chose to get there -- plus the one question its
                                  research could not answer from what it was told.

    AnswerWalker          records the answer to that question and re-runs the
                          whole chain over the enriched story, so a single "no, I
                          don't have ID" re-judges every gate and re-orders the
                          plan. The agent is handed the Q&A so it never asks
                          twice.

    MatchWalker           soft-matches open Needs against donor pledges, writes
                          a Matched edge and decrements the pledge. Nobody
                          schedules it and nobody clicks it: it is woken by the
                          three graph events that can change what a need can
                          reach --

                            NeedBroadcastWalker  a need lands on the commons
                            PledgeWalker         a pledge lands on the shelf
                            FollowUpWalker       escalation widens the radius

                          -- so whichever half of a match arrives second sets it
                          off, in whichever session that happened to be. It runs
                          the same either way: from a Need the only way out is
                          `BroadcastTo -> Org` and from an Org the only way to a
                          pledge is back down `RoutedThrough`, so there is no
                          session in which it can reach a Person.

    FulfillmentWalker     runs back in the seeker's session on their next poll.
                          Sees the Matched edge that appeared, rewrites the
                          plan, writes the nudge. Neither walker called the
                          other -- they only ever touched the same graph. Then
                          it wakes StrategyWalker, because a brief reasoned over
                          an open category is wrong the moment that category is
                          covered.

    FollowUpWalker        ages open Needs, asks the model *how* to escalate, and
                          acts on the answer -- widening the radius, rewording
                          the ask, or opening a second front in another
                          category. Its memory is the `escalations` counter that
                          survives every restart.
"""

import from core.graph {
    Activity, AnsweredQuestion, CaseStrategy, Contribution, Donor, Need, NeedCard,
    Org, Person, PlanStep, Requirement, SeekerBoard, CommunityView, StrategyView,
    OfferView,
    BroadcastTo, HasAnswer, HasNeed, HasStep, HasStrategy, Matched, Pledges,
    Requires, RoutedThrough,
    age_hours, age_label, need_code, now_iso, rewind
}
import from core.directory {
    audience_is_senior, commons_has_live_orgs, is_demo_org, sync_live_directory
}
import from core.commons {
    engine_report, ensure_commons, flush_engine_log, log_walker, org_cards,
    orgs_for, pledge_cards, recent_activity, _my_account
}
import from core.reason {
    EligibilityVerdict, LeakAudit, MatchVerdict, HelperOfferItem,
    audit_anonymization_safe, engine, escalation_strategy_safe, launch_match,
    launch_requirement, next_step_nudge_safe, read_helper_offers_safe,
    read_situation_safe, require_engine
}
import from core.agent { drain_tool_trace, plan_strategy_safe }
import from core.geo { zip_prefix_of }


glob CATEGORY_ORDER: list[str] = ["food", "shelter", "legal", "jobs"];

glob CATEGORY_NOUN: dict[str, str] = {
    "food": "groceries",
    "shelter": "a place to stay",
    "legal": "legal help",
    "jobs": "work"
};


# ===========================================================================
# Shared projections
# ===========================================================================

"""Project a Need down to the only shape the donor side is allowed to see."""
def need_card(nd: Need) -> NeedCard {
    via = [o.name for o in [nd ->:BroadcastTo:->]];
    matched_with = "";
    rationale = "";
    for e in [edge nd ->:Matched:->] {
        matched_with = e.pledge_desc;
        rationale = e.rationale;
    }
    return NeedCard(
        code=nd.code,
        category=nd.category,
        summary=nd.summary,
        urgency=nd.urgency,
        zip_prefix=nd.zip_prefix,
        household=nd.household,
        status=nd.status,
        via_org=via[0] if via else "unrouted",
        broadcast_tier=nd.broadcast_tier,
        escalations=nd.escalations,
        matched_with=matched_with,
        match_rationale=rationale,
        age_label=age_label(nd.created_at)
    );
}


def _rank(step: PlanStep) -> int {
    return step.rank;
}


"""Project the ReAct caseworker's stored brief, research path included."""
def strategy_view(cs: CaseStrategy) -> StrategyView {
    return StrategyView(
        headline=cs.headline,
        first_action=cs.first_action,
        ordered_actions=cs.ordered_actions,
        rely_on_community=cs.rely_on_community,
        risk=cs.risk,
        research_note=cs.research_note,
        research_path=cs.research_path,
        open_question=cs.open_question,
        question_why=cs.question_why,
        engine=cs.engine,
        at=cs.at
    );
}


"""Every question already put to this person, oldest first, as "Q -> A"."""
def answered_trail(person: Person) -> list[str] {
    rows = sorted(
        [person ->:HasAnswer:->],
        key=lambda (a: AnsweredQuestion) -> str { return a.at; }
    );
    return [f"{a.question} -> {a.answer}" for a in rows];
}


def build_board(person: Person) -> SeekerBoard {
    steps = sorted([person ->:HasStep:->], key=_rank);
    rep = engine_report();
    return SeekerBoard(
        person_id=jid(person),
        alias=person.alias,
        headline=person.headline,
        nudge=person.last_nudge,
        situation=person.situation,
        steps=steps,
        needs=[need_card(n) for n in [person ->:HasNeed:->]],
        activity=recent_activity(12),
        engine=rep.mode,
        has_plan=len(steps) > 0,
        strategy=[strategy_view(s) for s in [person ->:HasStrategy:->]],
        answered=answered_trail(person),
        privacy_leaks=person.anon_leaks,
        privacy_audited=person.anon_audited,
        engine_model=rep.model,
        engine_reason=rep.reason,
        engine_calls=rep.calls,
        engine_roles=rep.roles
    );
}


def _my_person -> Person | None {
    found = [root --> [?:Person]];
    return found[0] if found else None;
}


# ===========================================================================
# 1. EligibilityPathWalker
# ===========================================================================

walker:protect EligibilityPathWalker {
    """Walk Root -> Org -> Requirement, reasoning about this person at each gate.

    This is the walker that turns "here is a list of food banks" into "the
    closest one will turn you away at the door, here is what to do first".
    """

    has person_jid: str;
    has situation: str = "";
    has assets: str = "";
    has categories: list[str] = [];
    has zip_prefix: str = "";
    has prefer_senior: bool = False;
    has skip_demo_seeds: bool = False;
    has orgs_seen: int = 0;
    has gates_checked: int = 0;
    has blocked: int = 0;
    has seen_unblocks: list[str] = [];
    has made: list[PlanStep] = [];
    has reports: list[PlanStep] = [];

    can begin with Root entry {
        target = jobj(self.person_jid);
        if not isinstance(target, Person) {
            disengage;
        }
        # Fail before touching anything -- a missing key must not wipe the
        # person's existing plan out from under them.
        require_engine("judge_requirement");

        self.situation = target.situation;
        self.assets = ", ".join(target.assets) if target.assets else "nothing confirmed";
        self.categories = target.categories;
        self.zip_prefix = target.zip_prefix;
        asset_blob = (" ".join(target.assets) + " " + target.situation).lower();
        self.prefer_senior = (
            "senior" in asset_blob
            or "elderly" in asset_blob
            or "elder" in asset_blob
            or "retire" in asset_blob
        );
        # Once OpenStreetMap listings are on the commons, hide the fake 555
        # demo seeds so the plan is built from real contact info.
        self.skip_demo_seeds = commons_has_live_orgs();

        for stale in [target ->:HasStep:->] {
            del stale;
        }
        visit [root.shared --> [?:Org]];
    }

    can assess with Org entry {
        if here.category not in self.categories {
            skip;
        }
        if here.tier > 2 {
            skip;
        }
        if self.skip_demo_seeds and is_demo_org(here) {
            skip;
        }
        # Live listings sometimes omit a ZIP prefix — treat empty as in-area.
        if (
            self.zip_prefix
            and here.tier == 1
            and here.zip_prefix
            and here.zip_prefix != self.zip_prefix
        ) {
            skip;
        }

        person = jobj(self.person_jid);
        if not isinstance(person, Person) {
            disengage;
        }
        self.orgs_seen += 1;

        # Rank groups the plan by category, then by the order orgs were walked,
        # leaving a slot just above each org for the step that unblocks it.
        # Senior-audience orgs sort ahead when the person is a senior.
        band = CATEGORY_ORDER.index(here.category) if here.category in CATEGORY_ORDER else len(CATEGORY_ORDER);
        senior_boost = 0;
        if self.prefer_senior {
            blob = (here.name + " " + here.notes).lower();
            if "audience:senior" in blob or "senior" in blob or "elder" in blob {
                senior_boost = -400;
            }
        }
        base = (band * 1000) + senior_boost + (self.orgs_seen * 10);

        blockers: list[str] = [];
        unblocks: list[str] = [];
        notes: list[str] = [];

        # One org's gates are independent of each other, so launch every
        # judgement at once and collect after. With a real model behind
        # `judge_requirement_safe` this is the difference between one round
        # trip per org and one per requirement.
        gates = [here ->:Requires:->];
        pending = [
            launch_requirement(self.situation, self.assets, g.label, g.kind, g.workaround)
            for g in gates
        ];
        verdicts: list[EligibilityVerdict] = [wait f for f in pending];

        for (i, gate) in enumerate(gates) {
            self.gates_checked += 1;
            verdict = verdicts[i];
            if verdict.satisfied {
                notes.append(verdict.reasoning);
            } else {
                blockers.append(gate.label);
                notes.append(verdict.reasoning);
                action = verdict.unblock_action if verdict.unblock_action else gate.workaround;
                if action and gate.label not in self.seen_unblocks {
                    self.seen_unblocks.append(gate.label);
                    unblocks.append(gate.label + "||" + action);
                }
            }
        }

        # The blocker-clearing steps go IN FRONT of the org they unblock.
        for pair in unblocks {
            parts = pair.split("||");
            fix = person +>:HasStep:+> PlanStep(
                title=f"First: {parts[0].lower()}",
                detail=parts[1],
                category="documents",
                status="open",
                org_name=here.name,
                unblocks=here.name,
                unblock_category=here.category,
                reasoning=f"{here.name} turns people away at the door without this.",
                engine=engine(),
                rank=base - 5
            );
            self.made.append(fix);
        }

        blocked_now = len(blockers) > 0;
        if blocked_now {
            self.blocked += 1;
        }
        step = person +>:HasStep:+> PlanStep(
            title=here.name,
            detail=f"{here.address} - {here.hours}. {here.notes}",
            category=here.category,
            status="blocked" if blocked_now else "open",
            org_name=here.name,
            org_address=here.address,
            org_phone=here.phone,
            blocker=", ".join(blockers),
            reasoning=" ".join(notes) if notes else "No eligibility gates -- you can just show up.",
            engine=engine(),
            rank=base
        );
        self.made.append(step);
    }

    can wrap with Root exit {
        log_walker(
            "EligibilityPathWalker",
            f"checked {self.gates_checked} eligibility gates across {self.orgs_seen} orgs; {self.blocked} blocked, {len(self.seen_unblocks)} unblock steps inserted"
        );
    }
}


# ===========================================================================
# 2. NeedBroadcastWalker
# ===========================================================================

walker:protect NeedBroadcastWalker {
    """Turn every still-unmet category into an anonymized Need on the commons.

    Note what does NOT happen here: no notification is sent, no queue is
    published, nothing is pushed. The walker attaches `BroadcastTo` edges and
    then wakes the matcher *itself*. The need landing on the commons is the
    trigger -- no human is in the loop, and no scheduler is either.

    Running the matcher from the seeker's own session is safe for the same
    structural reason the whole app is: `MatchWalker` can only traverse
    `Need -> Org -> Contribution`, and there is no edge from any of those back
    to a `Person`. Reachability is what enforces the boundary, not whose session
    the walker happens to be running in.
    """

    has person_jid: str;
    has created: int = 0;
    has fanout: int = 0;
    has matched_now: int = 0;
    has opened: list[NeedCard] = [];
    has reports: list[NeedCard] = [];

    can begin with Root entry {
        person = jobj(self.person_jid);
        if not isinstance(person, Person) {
            disengage;
        }

        live: list[str] = [];
        for nd in [person ->:HasNeed:->] {
            if nd.status != "fulfilled" {
                live.append(nd.category);
            }
        }

        unmet: list[str] = [];
        for step in [person ->:HasStep:->] {
            if step.category in CATEGORY_ORDER and step.status in ["open", "blocked"] {
                if step.category not in unmet {
                    unmet.append(step.category);
                }
            }
        }

        fresh: list[Need] = [];
        for category in unmet {
            if category in live {
                continue;
            }
            need = root.shared ++> Need(
                category=category,
                summary=f"Needs {CATEGORY_NOUN.get(category, category)}. {person.anon_summary}",
                urgency=person.urgency,
                zip_prefix=person.zip_prefix,
                household=person.household,
                status="open",
                created_at=now_iso()
            );
            need.code = need_code(jid(need));
            # WritePerm: the matcher has to flip `status` and the FollowUpWalker
            # has to bump `escalations`, and either can be woken from a session
            # other than this one -- a helper's pledge, or a later escalation.
            grant(need, level=WritePerm);
            person +>:HasNeed:+> need;
            self.created += 1;

            for org in orgs_for(category, person.zip_prefix, 1) {
                need +>:BroadcastTo(tier=1):+> org;
                self.fanout += 1;
            }
            fresh.append(need);
        }

        if self.created > 0 {
            log_walker(
                "NeedBroadcastWalker",
                f"opened {self.created} anonymized need(s), wired to {self.fanout} local org(s) -- no identity crossed"
            );
            self.try_match([n.code for n in fresh]);
        }

        # Built AFTER the match attempt so the cards carry whatever status the
        # matcher just left on them, rather than a stale "open".
        self.opened = [need_card(n) for n in fresh];
    }

    """Wake the matcher on the needs that just landed. Never fatal.

    The eligibility plan is the promise this walker's caller is keeping; a
    matcher that cannot run (no engine, a provider blip) must cost the person a
    match attempt, not their plan. So it is logged honestly and swallowed --
    the need stays `open`, and the next trigger or the manual sweep retries it.
    """
    def try_match(codes: list[str]) {
        if not codes {
            return;
        }
        try {
            matcher = MatchWalker(
                only_codes=codes,
                emit=False,
                woke_on=f"{len(codes)} new need(s) landed on the commons"
            );
            root spawn matcher;
            self.matched_now = matcher.matched;
        } except Exception as e {
            log_walker(
                "engine",
                f"needs published, but the match they triggered could not run: {str(e)}"
            );
        }
    }
}


# ===========================================================================
# 3. StrategyWalker  (the ReAct caseworker)
# ===========================================================================

walker:protect StrategyWalker {
    """Run the tool-using caseworker agent, then persist its brief AND its research.

    This is the only walker that does not decide anything itself. It hands the
    situation to an agent holding four graph-reading tools and lets the agent
    choose what to investigate. What comes back is stored together with the tool
    trace, so the plan and the research behind it can be audited side by side.

    It is not an endpoint and there is no button for it. Two graph events run it,
    both of which mean "the facts this brief was reasoned over have changed":

        IntakeWalker        the person's story is new, or was just re-described
        FulfillmentWalker   a need got covered, so a category the agent planned
                            around is no longer open and the shelf it read has
                            been drawn down

    `AnswerWalker` is the third path only because it re-runs intake -- the answer
    becomes part of the story rather than a separate trigger.
    """

    has person_jid: str;

    # No `report` and no `reports`: every caller spawns this from inside another
    # walker, and a nested spawn's reports flow into the OUTER walker's response
    # stream rather than its own. Callers read the brief off `self.brief`.
    has brief: list[StrategyView] = [];

    can plan with Root entry {
        person = jobj(self.person_jid);
        if not isinstance(person, Person) {
            disengage;
        }
        require_engine("plan_strategy");

        # The answered trail goes in so the agent never re-asks a question this
        # person has already sat through, and treats past answers as fact.
        prior = answered_trail(person);
        brief = plan_strategy_safe(
            person.situation,
            ", ".join(person.categories),
            ", ".join(person.assets) if person.assets else "nothing confirmed",
            person.household,
            person.zip_prefix,
            "\n".join(prior) if prior else "nothing asked yet"
        );

        # The agent's own research path -- which graph reads it chose, in order.
        path = drain_tool_trace();

        # The previous brief is retired only now that a replacement exists. Doing
        # it up front is the obvious way to write this and it is wrong: the ReAct
        # loop can fail mid-tool-call, and on a re-plan that would leave the
        # person staring at no brief at all rather than at a slightly old one.
        for stale in [person ->:HasStrategy:->] {
            del stale;
        }

        saved = person +>:HasStrategy:+> CaseStrategy(
            headline=brief.headline,
            first_action=brief.first_action,
            ordered_actions=brief.ordered_actions,
            rely_on_community=brief.rely_on_community,
            risk=brief.risk,
            research_note=brief.research_note,
            research_path=path,
            open_question=brief.open_question,
            question_why=brief.question_why,
            engine=engine(),
            at=now_iso()
        );

        log_walker(
            "StrategyWalker",
            f"caseworker agent ran {len(path)} graph lookup(s) before committing to a "
            f"{len(brief.ordered_actions)}-step strategy; first move: \"{brief.first_action}\""
        );
        for line in path {
            log_walker("agent-tool", line);
        }
        if brief.open_question {
            log_walker(
                "StrategyWalker",
                f"its research left one thing unresolved, asking: \"{brief.open_question}\""
            );
        }

        flush_engine_log();
        self.brief.append(strategy_view(saved));
    }
}


# ===========================================================================
# 4. IntakeWalker  (the front door)
# ===========================================================================

walker:protect IntakeWalker {
    """Read the person's words, then hand off to the other three by spawning them."""

    has situation: str;
    has alias: str = "";

    # True only when `AnswerWalker` is driving: the enriched story it passes in
    # already contains the answer it just recorded, so the trail must survive.
    # A person re-describing by hand is doing the opposite -- restating their
    # situation is how they correct an answer they gave earlier -- so the default
    # is to clear it and let the agent ask again against the new facts.
    has keep_answers: bool = False;

    # Same nested-spawn rule as StrategyWalker: a nested walker's reports land in
    # the OUTER walker's stream, so `AnswerWalker` drives this with emit=False and
    # builds its own board afterwards.
    has emit: bool = True;
    has reports: list[SeekerBoard] = [];

    can start with Root entry {
        ensure_commons();
        acct = _my_account();
        name = self.alias if self.alias else (acct.display_name if acct is not None else "friend");

        read = read_situation_safe(self.situation);

        # The audit goes out now and is collected below, so finding or minting the
        # Person happens while the model call is in flight rather than behind it.
        #
        # Inline `flow` is safe here where the `launch_*` wrappers in
        # core/reason.jac are required elsewhere: the trap those wrappers exist to
        # avoid is a comprehension capturing its loop variable by reference, and
        # this is a single call with no loop. The role touches no graph state,
        # which is what makes it safe to overlap at all -- concurrent graph writes
        # are what trip the runtime's optimistic-concurrency check.
        # Pull the string out first: only plain values cross a `flow` boundary, and
        # handing the whole `SituationRead` obj over fails with E1308.
        proposed = read.anonymized_summary;
        pending_audit = flow audit_anonymization_safe(self.situation, proposed);

        person = _my_person();
        if person is None {
            person = root ++> Person(alias=name, situation=self.situation, created_at=now_iso());
        }

        # The audit is a SECOND model pass over the first one's anonymization, and
        # nothing reaches the commons until it has run: the privacy claim is a
        # checked invariant, not a promise, so whatever the auditor repairs is what
        # gets published, and what it caught is kept for the record.
        #
        # Everything that retires old state waits until after this resolves. The
        # audit can fail mid-flight on a provider blip, and a failure here must
        # leave the person the plan they already had rather than a half-wiped one
        # -- same rule EligibilityPathWalker follows before it clears the steps.
        audit = (wait pending_audit) as LeakAudit;
        published = audit.repaired_summary if audit.repaired_summary else read.anonymized_summary;

        # Re-describing re-plans from scratch: retire the old needs so the commons
        # never shows two live asks for the same household. (EligibilityPathWalker
        # and StrategyWalker do the same for the old steps and the old brief.)
        for stale in [person ->:HasNeed:->] {
            self.release_pledge(stale);
            del stale;
        }
        if not self.keep_answers {
            for prior in [person ->:HasAnswer:->] {
                del prior;
            }
        }

        person.alias = name;
        person.situation = self.situation;
        person.categories = read.categories;
        # Senior-only asks often omit an explicit need; default to food so
        # eligibility has categories to walk (senior meals / congregate dining).
        if not person.categories and audience_is_senior(self.situation, read.assets) {
            person.categories = ["food"];
        }
        person.household = read.household;
        # The location the person gave at signup wins over the one the model
        # inferred from their story. It was collected explicitly, with a
        # permission prompt, and it is the reason `question_guard` is allowed to
        # forbid the agent from ever asking where someone lives -- `agent.jac`
        # promises the model it "already has every location detail it is
        # permitted to hold", and this assignment is what makes that true.
        # `read.zip_prefix` stays as the fallback for a person who mentioned a
        # ZIP in their story but skipped the location step.
        from_account = zip_prefix_of(acct.location if acct is not None else "");
        person.zip_prefix = from_account if from_account else read.zip_prefix;
        person.assets = read.assets;
        person.anon_summary = published;
        person.headline = read.headline;
        person.urgency = read.urgency;
        person.last_nudge = "";
        person.anon_audited = True;
        person.anon_leaks = audit.leaks;

        # Keep Settings → Eligibility notes in sync with what intake just learned,
        # without overwriting notes the person already typed themselves.
        if acct is not None and not acct.eligibility_notes.strip() {
            note_bits: list[str] = [];
            if read.household > 0 {
                note_bits = note_bits + ["Household: " + str(read.household)];
            }
            # `person.zip_prefix`, not `read.zip_prefix`: the resolved area is
            # usually the one from the signup location, and the model's reading
            # is only the fallback. Reading it here would leave the note blank
            # for exactly the people whose area we are surest about.
            if person.zip_prefix {
                note_bits = note_bits + ["ZIP area: " + person.zip_prefix];
            }
            if read.assets {
                note_bits = note_bits + ["Has: " + ", ".join(read.assets)];
            }
            if note_bits {
                acct.eligibility_notes = "\n".join(note_bits);
            }
        }

        log_walker(
            "IntakeWalker",
            f"read a {read.urgency}-urgency situation -> {', '.join(read.categories)}; anonymized to: \"{published}\""
        );
        if audit.leaks {
            log_walker(
                "PrivacyAuditor",
                f"blocked {len(audit.leaks)} identity leak(s) before publishing: {'; '.join(audit.leaks)}"
            );
        } else {
            log_walker("PrivacyAuditor", "audited the public summary -- no identity leaks found");
        }

        # An unresolved area is the one case where the matcher stops filtering by
        # service area entirely, so it is said out loud rather than left to look
        # like a normal run: every tier-1 organisation will be offered, including
        # ones that will turn this person away at the door.
        if person.zip_prefix {
            log_walker(
                "IntakeWalker",
                f"service area {person.zip_prefix} "
                + ("from the location given at signup" if from_account else "inferred from their story")
            );
        } else {
            log_walker(
                "IntakeWalker",
                "no service area resolved -- tier-1 results are NOT filtered by area"
            );
        }

        # Pull real organisations from OpenStreetMap into the commons *before*
        # eligibility walks the graph, so senior / food / shelter searches land
        # on live listings rather than only the demo seed set.
        try {
            sync_live_directory(
                self.situation,
                person.categories,
                person.zip_prefix,
                person.assets
            );
        } except Exception as e {
            log_walker(
                "LiveDirectory",
                f"online directory lookup failed, continuing with seeded commons: {str(e)}"
            );
        }

        # The eligibility plan and the broadcast are the core promise -- if the
        # model cannot produce them, the whole submission should fail loudly,
        # not silently proceed with an empty plan.
        planner = EligibilityPathWalker(person_jid=jid(person));
        root spawn planner;

        broadcaster = NeedBroadcastWalker(person_jid=jid(person));
        root spawn broadcaster;

        # The caseworker agent's brief is additive -- the UI already renders it
        # as an optional 0-or-1-item card. A failure here (e.g. the ReAct loop
        # errors mid-tool-call) should not cost the person the eligibility plan
        # they already have; it is logged honestly instead of shown at all.
        try {
            strategist = StrategyWalker(person_jid=jid(person));
            root spawn strategist;
        } except Exception as e {
            log_walker("engine", f"caseworker agent failed, no brief this time: {str(e)}");
        }

        flush_engine_log();
        if self.emit {
            report build_board(person);
        }
    }

    """Give a retired need's units back to the donor who was holding them.

    A matched need has already taken `units` off a `Contribution`. Deleting it
    takes the `Matched` edge with it but leaves `remaining` decremented, so
    without this the shelf drains a little on every re-describe and eventually
    the matcher reports that nothing fits against pledges nobody ever used.
    """
    def release_pledge(stale: Need) -> None {
        units = 0;
        for e in [edge stale ->:Matched:->] {
            units = e.units;
        }
        if units <= 0 {
            return;
        }
        for pledge in [stale ->:Matched:->] {
            pledge.remaining = min(pledge.capacity, pledge.remaining + units);
            log_walker(
                "IntakeWalker",
                f"retired {stale.code} and returned {units} unit(s) to \"{pledge.description}\" -- {pledge.remaining} available again"
            );
        }
    }
}


# ===========================================================================
# 5. AnswerWalker  (the loop that makes the question worth asking)
# ===========================================================================

walker:protect AnswerWalker {
    """Take the answer to the agent's open question and re-plan on top of it.

    This is what makes the question more than decoration. The answer is recorded
    as a node, folded into the person's own narrative, and then the *entire*
    pipeline runs again over the enriched story: intake re-reads it, every
    eligibility gate is re-judged against the new fact, needs are rebuilt, and the
    agent produces a fresh strategy that is handed the Q&A so it cannot ask twice.

    So answering "no, I don't have a photo ID" does not tick a box -- it demotes
    every org that demands one and promotes the no-barrier pantry, because those
    were always conclusions about the graph rather than stored answers.
    """

    has answer: str;
    has question: str = "";
    has reports: list[SeekerBoard] = [];

    can apply with Root entry {
        person = _my_person();
        if person is None {
            disengage;
        }
        clean = self.answer.strip();
        if not clean {
            report build_board(person);
            disengage;
        }

        # Prefer the question the agent actually stored over whatever the client
        # echoed back, so the record cannot drift from what was really asked.
        asked = self.question;
        for cs in [person ->:HasStrategy:->] {
            if cs.open_question {
                asked = cs.open_question;
            }
        }
        if not asked {
            asked = "(unprompted detail)";
        }

        person +>:HasAnswer:+> AnsweredQuestion(
            question=asked,
            answer=clean,
            at=now_iso()
        );
        log_walker("AnswerWalker", f"answered \"{asked}\" -> \"{clean}\"; re-planning from scratch");

        # Fold it into the narrative rather than patching `assets` by hand: the
        # intake role already knows how to turn prose into structured facts, so the
        # answer flows through the same path as everything the person volunteered.
        enriched = f"{person.situation} In answer to \"{asked}\": {clean}.";

        replan = IntakeWalker(
            situation=enriched, alias=person.alias, emit=False, keep_answers=True
        );
        root spawn replan;

        fresh = _my_person();
        flush_engine_log();
        if fresh is not None {
            report build_board(fresh);
        }
    }
}


# ===========================================================================
# 6. MatchWalker  (runs in whichever session woke it, never sees a Person)
# ===========================================================================

walker:protect MatchWalker {
    """Soft-match open needs against open pledges, through the org in between.

    Reachability, not a filter, is what keeps this walker honest: from a `Need`
    the only way out is `BroadcastTo -> Org`, and from an `Org` the only way to
    a pledge is back down `RoutedThrough`. There is no edge from here to a
    `Person`, so no amount of traversal reaches one.
    """

    has only_code: str = "";

    # Set when something *else* woke this walker: the codes that just changed,
    # or the pledge that just appeared. Empty means a full sweep of the commons.
    has only_codes: list[str] = [];
    has from_pledge: str = "";

    # Non-empty when this run was triggered by a graph event rather than a
    # person. It is the sentence written into the activity feed, so the demo can
    # show *what* woke the matcher, not just that it ran.
    has woke_on: str = "";

    # Same trap StrategyWalker documents: a nested spawn's reports land in the
    # OUTER walker's response stream. Every autonomous trigger sets this False
    # and reads `self.cards` / `self.matched` off the walker instead.
    has emit: bool = True;

    has considered: int = 0;
    has matched: int = 0;
    has notes: list[str] = [];
    has cards: list[NeedCard] = [];
    has reports: list[NeedCard] = [];

    can begin with Root entry {
        require_engine("judge_match");
        if self.woke_on {
            log_walker("MatchWalker", f"woke on its own -- {self.woke_on}");
        }

        if not self.from_pledge {
            visit [root.shared --> [?:Need]];
            return;
        }

        # Pledge-triggered: the new pledge's own reachability IS the candidate
        # set. Up its RoutedThrough edges to the orgs holding it, then back down
        # every BroadcastTo aimed at those same orgs. No scan and no index --
        # it is the matcher's usual traversal run backwards from the other end.
        host = jobj(self.from_pledge);
        if not isinstance(host, Contribution) {
            disengage;
        }
        reachable: list[Need] = [];
        seen_needs: list[str] = [];
        for org in [host ->:RoutedThrough:->] {
            for nd in [org <-:BroadcastTo:<-] {
                if jid(nd) not in seen_needs {
                    seen_needs.append(jid(nd));
                    reachable.append(nd);
                }
            }
        }
        visit reachable;
    }

    can consider with Need entry {
        if here.status != "open" {
            skip;
        }
        if self.only_code and here.code != self.only_code {
            skip;
        }
        if self.only_codes and here.code not in self.only_codes {
            skip;
        }

        best: Contribution | None = None;
        best_score = 0;
        best_units = 0;
        best_why = "";

        # Reachable pledges: out to the orgs this need was broadcast to, then
        # back down the RoutedThrough edges. Deduped, because two orgs can hold
        # the same pledge.
        candidates: list[Contribution] = [];
        seen: list[str] = [];
        for org in [here ->:BroadcastTo:->] {
            for pledge in [org <-:RoutedThrough:<-] {
                if pledge.remaining > 0 and jid(pledge) not in seen {
                    seen.append(jid(pledge));
                    candidates.append(pledge);
                }
            }
        }

        # Score every candidate in parallel, then pick.
        scoring = [
            launch_match(
                here.summary, here.category, here.household,
                c.kind, c.description, c.notes, c.remaining
            )
            for c in candidates
        ];
        judged: list[MatchVerdict] = [wait f for f in scoring];

        passed_here: list[str] = [];
        for (i, pledge) in enumerate(candidates) {
            self.considered += 1;
            verdict = judged[i];
            if verdict.fits and verdict.score > best_score and verdict.units > 0 {
                best = pledge;
                best_score = verdict.score;
                best_units = verdict.units;
                best_why = verdict.rationale;
            } elif not verdict.fits {
                passed_here.append(f"{here.code}: passed on \"{pledge.description}\" -- {verdict.rationale}");
            }
        }
        self.notes = self.notes + passed_here;

        # What the matcher DECLINED is the half worth reading -- "right
        # category, unusable for this household" is exactly what a keyword
        # matcher gets wrong. These go into the shared feed and not just onto
        # `self.notes`, because an autonomous run has no caller reading its
        # fields: it is spawned from inside another walker and nobody unwraps it.
        for note in passed_here {
            log_walker("MatchWalker", note);
        }

        if best is None {
            skip;
        }

        winner = best as Contribution;
        here +>:Matched(
            pledge_desc=winner.description,
            rationale=best_why,
            units=best_units,
            score=best_score,
            engine=engine(),
            at=now_iso()
        ):+> winner;
        winner.remaining = winner.remaining - best_units;
        here.status = "matched";
        here.fulfillment_note = best_why;
        self.matched += 1;

        log_walker(
            "MatchWalker",
            f"matched {here.code} to \"{winner.description}\" (fit {best_score}/100, {best_units} units); {winner.remaining} left on that pledge"
        );
        card = need_card(here);
        self.cards.append(card);
        if self.emit {
            report card;
        }
    }

    can wrap with Root exit {
        if self.matched == 0 and self.considered > 0 {
            log_walker(
                "MatchWalker",
                f"considered {self.considered} pledge/need pairs, matched none -- nothing on the shelf fits"
            );
        } elif self.matched == 0 and self.woke_on {
            # An autonomous run that found nothing still says so, otherwise the
            # "woke on its own" line above dangles with no outcome under it.
            # Worded for both directions -- the thing with no counterpart is a
            # need when a need woke it, and a pledge when a pledge did.
            log_walker(
                "MatchWalker",
                "nothing reachable to pair it with yet -- everything stays open"
            );
        }
        flush_engine_log();
    }
}


# ===========================================================================
# 7. FulfillmentWalker  (runs as the seeker, on their poll)
# ===========================================================================

walker:protect FulfillmentWalker {
    """Reconcile the person's plan when they accept a helper match.

    The seeker's UI polls this with an empty `accept_code` to refresh the board
    without settling anything -- matched helper offers stay visible so the person
    can Accept them. Passing `accept_code` (a Need.code) settles that one match:
    covers the matching plan steps, writes the one-line `last_nudge` update, and
    re-wakes the caseworker around what is left.
    """

    has accept_code: str = "";
    has resolved: list[str] = [];
    has restrategized: bool = False;
    has reports: list[SeekerBoard] = [];

    can begin with Root entry {
        visit [root --> [?:Person]];
    }

    can reconcile with Person entry {
        visit [here ->:HasNeed:->];
    }

    can settle with Need entry {
        # Polls never auto-settle -- the seeker must Accept the helper offer.
        if not self.accept_code or here.code != self.accept_code {
            skip;
        }
        if here.status != "matched" {
            skip;
        }
        owners = [here <-:HasNeed:<-];
        if not owners {
            skip;
        }
        person = owners[0];

        noun = CATEGORY_NOUN.get(here.category, here.category);

        # Work out what the next open step WOULD be once this fulfillment lands,
        # without mutating anything yet -- mirrors the covering/optional rules
        # below exactly, so the nudge can be generated before anything commits.
        next_open = "";
        for step in sorted([person ->:HasStep:->], key=_rank) {
            would_be_covered = step.category == here.category and step.status in ["open", "blocked"];
            would_be_optional = step.unblocks and step.unblock_category == here.category and step.status == "open";
            if step.status == "open" and not would_be_covered and not would_be_optional and not next_open {
                next_open = step.title;
            }
        }

        # The nudge is the only part of settling a match that needs the model.
        # If it is not available right now, mutate NOTHING -- the Need stays
        # "matched" and this same check retries on the person's next poll, with
        # no fabricated text standing in for the real one.
        try {
            nudge = next_step_nudge_safe(noun, next_open);
        } except Exception as e {
            log_walker(
                "engine",
                f"{here.code} matched but the model is unavailable for the update text ({str(e)}) -- will retry"
            );
            skip;
        }

        covered = 0;
        for step in [person ->:HasStep:->] {
            if step.category == here.category and step.status in ["open", "blocked"] {
                step.status = "covered";
                step.detail = here.fulfillment_note if here.fulfillment_note else step.detail;
                covered += 1;
            }
            if step.unblocks and step.unblock_category == here.category and step.status == "open" {
                step.status = "optional";
            }
        }

        here.status = "fulfilled";
        self.resolved.append(noun);
        person.last_nudge = nudge;

        log_walker(
            "FulfillmentWalker",
            f"{here.code} fulfilled -> rewrote {covered} plan step(s); next open step is \"{next_open if next_open else 'nothing'}\""
        );
    }

    """Re-run the caseworker over what is actually left. Never fatal.

    The plan rewrite is the promise this walker keeps; a caseworker that cannot
    run right now must cost the person a fresher brief, not the update they were
    waiting for. `StrategyWalker` retires the old brief only once the new one
    exists, so a failure here leaves the previous one on screen rather than
    blanking the card.
    """
    def restrategize(person: Person) {
        try {
            strategist = StrategyWalker(person_jid=jid(person));
            root spawn strategist;
            self.restrategized = len(strategist.brief) > 0;
            if self.restrategized {
                log_walker(
                    "FulfillmentWalker",
                    f"{' and '.join(self.resolved)} now covered -- woke the caseworker to re-plan around what is left"
                );
            }
        } except Exception as e {
            log_walker(
                "engine",
                f"plan updated, but the caseworker could not re-plan on it: {str(e)}"
            );
        }
    }

    can wrap with Root exit {
        person = _my_person();
        # Only on the one poll where something actually settled. Every other
        # tick of the 3s poll does no model work at all and returns immediately.
        if person is not None and self.resolved {
            self.restrategize(person);
        }

        flush_engine_log();
        if person is not None {
            report build_board(person);
        } else {
            # Always report a board -- the intake screen reads the engine badge
            # off it before any Person exists.
            rep = engine_report();
            report SeekerBoard(
                person_id="",
                alias="",
                headline="",
                nudge="",
                activity=recent_activity(12),
                engine=rep.mode,
                engine_model=rep.model,
                engine_reason=rep.reason,
                engine_calls=rep.calls,
                engine_roles=rep.roles
            );
        }
    }
}


# ===========================================================================
# 8. FollowUpWalker  (the one with memory)
# ===========================================================================

walker:protect FollowUpWalker {
    """Age open needs, then ask the model *how* to escalate and act on the answer.

    `escalations` and `broadcast_tier` live on the Need node, so this walker
    behaves differently on its second run than its first -- across processes,
    across restarts, with no scheduler and no external store. That is the whole
    point of running it on a persistent graph.

    The escalation itself is a judgement, not an increment. A shelter need that
    nobody answered may be better relieved by legal help that stops the eviction
    than by shouting the same ask at more shelters, and the model is the thing
    that decides that. The counter is memory; the strategy is reasoning.
    """

    has simulate_hours: int = 0;
    has threshold_hours: int = 24;
    has escalated: int = 0;
    has fanout: int = 0;
    has reworded: int = 0;
    has second_fronts: int = 0;
    has rematched: int = 0;

    # Codes whose reachable org set actually grew this run -- the only ones
    # worth re-matching, since nothing else about the shelf changed.
    has widened: list[str] = [];
    has reports: list[NeedCard] = [];

    can begin with Root entry {
        require_engine("escalation_strategy");
        visit [root.shared --> [?:Need]];
    }

    can check with Need entry {
        if here.status != "open" {
            skip;
        }
        if self.simulate_hours > 0 {
            here.created_at = rewind(here.created_at, self.simulate_hours);
        }
        hours = int(age_hours(here.created_at));
        if hours < self.threshold_hours {
            skip;
        }
        if here.broadcast_tier >= 3 {
            skip;
        }

        already = [o.name for o in [here ->:BroadcastTo:->]];
        plan = escalation_strategy_safe(
            here.summary,
            here.category,
            here.urgency,
            hours,
            here.escalations,
            ", ".join(already) if already else "none"
        );

        here.escalations += 1;
        if here.urgency == "medium" {
            here.urgency = "high";
        } elif here.urgency == "high" {
            here.urgency = "critical";
        }

        # Reword the public ask if the model thinks the current phrasing is what
        # is failing. Still anonymous -- it only ever rewrites the summary that
        # already passed the privacy auditor.
        if plan.reword_as {
            here.summary = plan.reword_as;
            self.reworded += 1;
        }

        added = 0;
        if plan.widen_radius {
            here.broadcast_tier += 1;
            for org in orgs_for(here.category, "", here.broadcast_tier) {
                if org.name in already {
                    continue;
                }
                here +>:BroadcastTo(tier=here.broadcast_tier):+> org;
                added += 1;
            }
        }

        # A second front: wire this same need to orgs in a *different* category
        # that would relieve the same underlying problem.
        if plan.also_try_category and plan.also_try_category != here.category {
            for org in orgs_for(plan.also_try_category, "", here.broadcast_tier) {
                if org.name in already {
                    continue;
                }
                here +>:BroadcastTo(tier=here.broadcast_tier):+> org;
                added += 1;
            }
            self.second_fronts += 1;
        }

        self.escalated += 1;
        self.fanout += added;
        if added > 0 {
            self.widened.append(here.code);
        }

        detail = (
            f"{here.code} unfilled after {hours}h (escalation #{here.escalations}) -> "
            f"{'radius widened to tier ' + str(here.broadcast_tier) if plan.widen_radius else 'radius held'}, "
            f"+{added} org(s)"
        );
        if plan.also_try_category {
            detail += f"; opened a second front in {plan.also_try_category}";
        }
        if plan.reword_as {
            detail += "; reworded the public ask";
        }
        log_walker("FollowUpWalker", detail);
        log_walker("FollowUpWalker", f"reasoning: {plan.reasoning}");
        report need_card(here);
    }

    can wrap with Root exit {
        # Widening the radius is a reachability change like any other: orgs that
        # were not on this need's horizon a moment ago are now, and any pledge
        # routed through them just became a candidate. So escalating retries the
        # match itself rather than waiting for someone to notice.
        if self.widened {
            try {
                matcher = MatchWalker(
                    only_codes=self.widened,
                    emit=False,
                    woke_on=f"{len(self.widened)} escalated need(s) can now reach further orgs"
                );
                root spawn matcher;
                self.rematched = matcher.matched;
            } except Exception as e {
                log_walker(
                    "engine",
                    f"escalated, but the match it triggered could not run: {str(e)}"
                );
            }
        }
        flush_engine_log();
    }
}


# ===========================================================================
# Read endpoints for the two views
# ===========================================================================

walker:protect CommunityBoard {
    """Everything the volunteer/donor side renders. Returns NeedCards, not Needs."""

    has reports: list[CommunityView] = [];

    can build with Root entry {
        ensure_commons();
        acct = _my_account();
        rep = engine_report();
        cards = [need_card(n) for n in [root.shared --> [?:Need]]];
        report CommunityView(
            display_name=acct.display_name if acct is not None else "volunteer",
            needs=cards,
            pledges=pledge_cards(),
            orgs=org_cards(),
            open_count=len([c for c in cards if c.status == "open"]),
            matched_count=len([c for c in cards if c.status == "matched"]),
            fulfilled_count=len([c for c in cards if c.status == "fulfilled"]),
            activity=recent_activity(14),
            engine=rep.mode,
            engine_model=rep.model,
            engine_reason=rep.reason,
            engine_calls=rep.calls,
            engine_roles=rep.roles
        );
    }
}


walker:protect PledgeWalker {
    """A helper puts something on the shelf, routed through an org.

    Putting it on the shelf IS running the matcher. The helper does not get a
    button to press afterwards: the moment the `RoutedThrough` edge exists, this
    walker wakes `MatchWalker` scoped to exactly the needs that pledge can now
    reach. The other trigger is `NeedBroadcastWalker`, from the opposite side --
    between them, whichever half of a match arrives second sets it off.
    """

    has kind: str;
    has description: str;
    has capacity: int;
    has org_id: str;
    has notes: str = "";
    has matched_now: int = 0;
    has matched_codes: list[str] = [];
    has reports: list[str] = [];

    can pledge with Root entry {
        ensure_commons();
        acct = _my_account();
        donors = [root --> [?:Donor]];
        donor = donors[0] if donors else (
            root ++> Donor(name=acct.display_name if acct is not None else "volunteer")
        );

        contribution = root.shared ++> Contribution(
            kind=self.kind,
            description=self.description,
            capacity=max(1, self.capacity),
            remaining=max(1, self.capacity),
            notes=self.notes
        );
        grant(contribution, level=WritePerm);
        # The donor edge points OUT of the private root into the commons, so the
        # pledge is public and the person who made it is not.
        donor +>:Pledges:+> contribution;

        host = jobj(self.org_id);
        if isinstance(host, Org) {
            contribution +>:RoutedThrough:+> host;
            log_walker(
                "PledgeWalker",
                f"new pledge on the shelf: \"{self.description}\" x{self.capacity}, routed through {host.name}"
            );
        }

        # Same rule as the need side: the pledge appearing is itself the
        # trigger. Swallowed on failure -- a matcher that cannot run must not
        # cost the helper the pledge they just made.
        try {
            matcher = MatchWalker(
                from_pledge=jid(contribution),
                emit=False,
                woke_on=f"a pledge landed on the shelf: \"{self.description}\""
            );
            root spawn matcher;
            self.matched_now = matcher.matched;
            self.matched_codes = [c.code for c in matcher.cards];
        } except Exception as e {
            log_walker(
                "engine",
                f"pledge is on the shelf, but the match it triggered could not run: {str(e)}"
            );
        }
        report jid(contribution);
    }
}


walker:protect RetirePledgeWalker {
    """Remove an offer from active matching without deleting history."""

    has pledge_id: str;
    has reports: list[str] = [];

    can retire with Root entry {
        target = jobj(self.pledge_id);
        if isinstance(target, Contribution) {
            target.remaining = 0;
            log_walker("RetirePledgeWalker", f"retired pledge {self.pledge_id}");
            report self.pledge_id;
        }
    }
}


walker:protect HelperOfferWalker {
    """Turn a volunteer's free-text offer into expandable OfferViews + pledges."""

    has text: str;
    has reports: list[OfferView] = [];
    has reply: str = "";

    can start with Root entry {
        ensure_commons();
        require_engine("read_helper_offers");
        acct = _my_account();
        donors = [root --> [?:Donor]];
        donor = donors[0] if donors else (
            root ++> Donor(name=acct.display_name if acct is not None else "volunteer")
        );

        read = read_helper_offers_safe(self.text);
        self.reply = read.reply;
        orgs = [root.shared --> [?:Org]];
        host = orgs[0] if orgs else None;

        for (i, item) in enumerate(read.offers) {
            kind = item.kind if item.kind in ["food", "goods", "funds", "time"] else "time";
            detail_notes = item.notes;
            if item.details {
                joined = " | ".join(item.details);
                detail_notes = (detail_notes + " — " + joined) if detail_notes else joined;
            }
            contribution = root.shared ++> Contribution(
                kind=kind,
                description=item.name + ": " + item.description,
                capacity=1,
                remaining=1,
                notes=detail_notes
            );
            grant(contribution, level=WritePerm);
            donor +>:Pledges:+> contribution;
            if host is not None {
                contribution +>:RoutedThrough:+> host;
            }
            report OfferView(
                id="offer-" + str(i) + "-" + jid(contribution)[-8:],
                name=item.name,
                kind=kind,
                description=item.description,
                details=item.details,
                notes=item.notes,
                pledge_id=jid(contribution)
            );
        }
        log_walker(
            "HelperOfferWalker",
            f"extracted {len(read.offers)} offer(s) from volunteer text"
        );
    }
}
