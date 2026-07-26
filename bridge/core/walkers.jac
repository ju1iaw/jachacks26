"""Bridge - the walkers.

Six walkers, distinct jobs, no direct calls between most of them. They
coordinate by reading and writing the same graph:

    IntakeWalker          person's words  ->  Person node
      |
      +-- EligibilityPathWalker   Root -> Org -> Requirement, reasons at each
      |                           gate, writes a PlanStep per org (blocked ones
      |                           get an unblock step in front of them)
      |
      +-- NeedBroadcastWalker     turns every still-unmet category into an
                                  anonymized Need on the commons and wires it
                                  to nearby orgs. The topology IS the message.

    MatchWalker           runs in a *different user's session* (the helper's).
                          Walks open Needs, soft-matches donor pledges, writes
                          a Matched edge and decrements the pledge.

    FulfillmentWalker     runs back in the seeker's session on their next poll.
                          Sees the Matched edge that appeared, rewrites the
                          plan, writes the nudge. Neither walker called the
                          other -- they only ever touched the same graph.

    FollowUpWalker        ages open Needs and escalates the broadcast radius on
                          its own. Its memory is the `escalations` counter that
                          survives every restart.
"""

import from core.graph {
    Activity, Contribution, Donor, Need, NeedCard, Org, Person, PlanStep,
    Requirement, SeekerBoard, CommunityView,
    BroadcastTo, HasNeed, HasStep, Matched, Pledges, Requires, RoutedThrough,
    age_hours, age_label, need_code, now_iso, rewind
}
import from core.commons {
    ensure_commons, log_walker, org_cards, orgs_for, pledge_cards,
    recent_activity, _my_account
}
import from core.reason {
    EligibilityVerdict, MatchVerdict,
    engine, launch_match, launch_requirement, next_step_nudge_safe,
    read_situation_safe
}


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


def build_board(person: Person) -> SeekerBoard {
    steps = sorted([person ->:HasStep:->], key=_rank);
    return SeekerBoard(
        person_id=jid(person),
        alias=person.alias,
        headline=person.headline,
        nudge=person.last_nudge,
        situation=person.situation,
        steps=steps,
        needs=[need_card(n) for n in [person ->:HasNeed:->]],
        activity=recent_activity(12),
        engine=engine(),
        has_plan=len(steps) > 0
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
        self.situation = target.situation;
        self.assets = ", ".join(target.assets) if target.assets else "nothing confirmed";
        self.categories = target.categories;
        self.zip_prefix = target.zip_prefix;

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
        if self.zip_prefix and here.tier == 1 and here.zip_prefix != self.zip_prefix {
            skip;
        }

        person = jobj(self.person_jid);
        if not isinstance(person, Person) {
            disengage;
        }
        self.orgs_seen += 1;

        # Rank groups the plan by category, then by the order orgs were walked,
        # leaving a slot just above each org for the step that unblocks it.
        band = CATEGORY_ORDER.index(here.category) if here.category in CATEGORY_ORDER else len(CATEGORY_ORDER);
        base = (band * 1000) + (self.orgs_seen * 10);

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
    stops. The graph topology is the message bus -- the helper's MatchWalker
    finds the need by traversing, in a completely separate request.
    """

    has person_jid: str;
    has created: int = 0;
    has fanout: int = 0;
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
            # WritePerm: the helper's MatchWalker has to flip `status` and the
            # FollowUpWalker has to bump `escalations` from other sessions.
            grant(need, level=WritePerm);
            person +>:HasNeed:+> need;
            self.created += 1;

            for org in orgs_for(category, person.zip_prefix, 1) {
                need +>:BroadcastTo(tier=1):+> org;
                self.fanout += 1;
            }
            self.opened.append(need_card(need));
        }

        if self.created > 0 {
            log_walker(
                "NeedBroadcastWalker",
                f"opened {self.created} anonymized need(s), wired to {self.fanout} local org(s) -- no identity crossed"
            );
        }
    }
}


# ===========================================================================
# 3. IntakeWalker  (the front door)
# ===========================================================================

walker:protect IntakeWalker {
    """Read the person's words, then hand off to the other two by spawning them."""

    has situation: str;
    has alias: str = "";
    has reports: list[SeekerBoard] = [];

    can start with Root entry {
        ensure_commons();
        acct = _my_account();
        name = self.alias if self.alias else (acct.display_name if acct is not None else "friend");

        read = read_situation_safe(self.situation);

        person = _my_person();
        if person is None {
            person = root ++> Person(alias=name, situation=self.situation, created_at=now_iso());
        } else {
            # Re-describing your situation re-plans from scratch: retire the old
            # needs so the commons never shows two live asks for the same thing.
            # (EligibilityPathWalker does the same for the old plan steps.)
            for stale in [person ->:HasNeed:->] {
                del stale;
            }
        }
        person.alias = name;
        person.situation = self.situation;
        person.categories = read.categories;
        person.household = read.household;
        person.zip_prefix = read.zip_prefix;
        person.assets = read.assets;
        person.anon_summary = read.anonymized_summary;
        person.headline = read.headline;
        person.urgency = read.urgency;
        person.last_nudge = "";

        log_walker(
            "IntakeWalker",
            f"read a {read.urgency}-urgency situation -> {', '.join(read.categories)}; anonymized to: \"{read.anonymized_summary}\""
        );

        planner = EligibilityPathWalker(person_jid=jid(person));
        root spawn planner;

        broadcaster = NeedBroadcastWalker(person_jid=jid(person));
        root spawn broadcaster;

        report build_board(person);
    }
}


# ===========================================================================
# 4. MatchWalker  (runs as the helper, never sees a Person)
# ===========================================================================

walker:protect MatchWalker {
    """Soft-match open needs against open pledges, through the org in between.

    Reachability, not a filter, is what keeps this walker honest: from a `Need`
    the only way out is `BroadcastTo -> Org`, and from an `Org` the only way to
    a pledge is back down `RoutedThrough`. There is no edge from here to a
    `Person`, so no amount of traversal reaches one.
    """

    has only_code: str = "";
    has considered: int = 0;
    has matched: int = 0;
    has notes: list[str] = [];
    has reports: list[NeedCard] = [];

    can begin with Root entry {
        visit [root.shared --> [?:Need]];
    }

    can consider with Need entry {
        if here.status != "open" {
            skip;
        }
        if self.only_code and here.code != self.only_code {
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

        for (i, pledge) in enumerate(candidates) {
            self.considered += 1;
            verdict = judged[i];
            if verdict.fits and verdict.score > best_score and verdict.units > 0 {
                best = pledge;
                best_score = verdict.score;
                best_units = verdict.units;
                best_why = verdict.rationale;
            } elif not verdict.fits {
                self.notes.append(f"{here.code}: passed on \"{pledge.description}\" -- {verdict.rationale}");
            }
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
        report need_card(here);
    }

    can wrap with Root exit {
        if self.matched == 0 and self.considered > 0 {
            log_walker(
                "MatchWalker",
                f"considered {self.considered} pledge/need pairs, matched none -- nothing on the shelf fits"
            );
        }
    }
}


# ===========================================================================
# 5. FulfillmentWalker  (runs as the seeker, on their poll)
# ===========================================================================

walker:protect FulfillmentWalker {
    """Reconcile the person's plan against whatever the graph now says.

    The seeker's UI polls this. It is the *only* thing that makes the plan
    change in real time -- and it works purely by noticing `Matched` edges that
    some other user's walker attached since the last poll.
    """

    has resolved: list[str] = [];
    has reports: list[SeekerBoard] = [];

    can begin with Root entry {
        visit [root --> [?:Person]];
    }

    can reconcile with Person entry {
        visit [here ->:HasNeed:->];
    }

    can settle with Need entry {
        if here.status != "matched" {
            skip;
        }
        owners = [here <-:HasNeed:<-];
        if not owners {
            skip;
        }
        person = owners[0];

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
        noun = CATEGORY_NOUN.get(here.category, here.category);
        self.resolved.append(noun);

        next_open = "";
        for step in sorted([person ->:HasStep:->], key=_rank) {
            if step.status == "open" and not next_open {
                next_open = step.title;
            }
        }
        person.last_nudge = next_step_nudge_safe(noun, next_open);

        log_walker(
            "FulfillmentWalker",
            f"{here.code} fulfilled -> rewrote {covered} plan step(s); next open step is \"{next_open if next_open else 'nothing'}\""
        );
    }

    can wrap with Root exit {
        person = _my_person();
        if person is not None {
            report build_board(person);
        } else {
            # Always report a board -- the intake screen reads `engine` off it
            # before any Person exists.
            report SeekerBoard(
                person_id="",
                alias="",
                headline="",
                nudge="",
                activity=recent_activity(12),
                engine=engine()
            );
        }
    }
}


# ===========================================================================
# 6. FollowUpWalker  (the one with memory)
# ===========================================================================

walker:protect FollowUpWalker {
    """Age open needs and widen their broadcast radius when nothing came back.

    `escalations` and `broadcast_tier` live on the Need node, so this walker
    behaves differently on its second run than its first -- across processes,
    across restarts, with no scheduler and no external store. That is the whole
    point of running it on a persistent graph.
    """

    has simulate_hours: int = 0;
    has threshold_hours: int = 24;
    has escalated: int = 0;
    has fanout: int = 0;
    has reports: list[NeedCard] = [];

    can begin with Root entry {
        visit [root.shared --> [?:Need]];
    }

    can check with Need entry {
        if here.status != "open" {
            skip;
        }
        if self.simulate_hours > 0 {
            here.created_at = rewind(here.created_at, self.simulate_hours);
        }
        if age_hours(here.created_at) < self.threshold_hours {
            skip;
        }
        if here.broadcast_tier >= 3 {
            skip;
        }

        here.escalations += 1;
        here.broadcast_tier += 1;
        if here.urgency == "medium" {
            here.urgency = "high";
        } elif here.urgency == "high" {
            here.urgency = "critical";
        }

        already = [o.name for o in [here ->:BroadcastTo:->]];
        added = 0;
        for org in orgs_for(here.category, "", here.broadcast_tier) {
            if org.name in already {
                continue;
            }
            here +>:BroadcastTo(tier=here.broadcast_tier):+> org;
            added += 1;
        }
        self.escalated += 1;
        self.fanout += added;

        log_walker(
            "FollowUpWalker",
            f"{here.code} unfilled after {int(age_hours(here.created_at))}h (escalation #{here.escalations}) -> radius widened to tier {here.broadcast_tier}, +{added} org(s)"
        );
        report need_card(here);
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
            engine=engine()
        );
    }
}


walker:protect PledgeWalker {
    """A helper puts something on the shelf, routed through an org."""

    has kind: str;
    has description: str;
    has capacity: int;
    has org_id: str;
    has notes: str = "";
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
        report jid(contribution);
    }
}
