"""End-to-end smoke run of the whole Bridge walker chain on one local graph.

    rm -rf .jac && jac run scripts/smoke.jac      # always start clean

Under `jac run` there is one root and `root.shared is root`, so both "users"
share a graph -- fine for exercising the walkers, but the real per-user
isolation only shows up under `jac start`. See scripts/demo_flow.sh for that.

**Reset between runs.** Re-running this script over a `.jac/` left behind by a
previous run intermittently dies at commit with
`WriteConflict: anchor ... changed concurrently (expected v1, found v2)`. It
happens when re-intake deletes the previous run's Needs while several of them are
also being escalated, and it reproduces identically on the pre-byLLM version of
this code -- so it is a property of re-running a `jac run` script against a
persisted store, which the Jac docs warn about ("Re-running a script duplicates
its nodes ... reset with `jac clean --all`"), not of the walker logic.

It does **not** affect the server. `scripts/demo_flow.sh` drives the same chain
through the API as two separate logged-in users, repeatedly, against a graph that
persists between calls, and stays clean -- that is the path the demo runs on.
"""

import sys;
import from core.commons { choose_role, ensure_commons, engine_report }
import from core.walkers {
    AnswerWalker, CommunityBoard, FollowUpWalker, FulfillmentWalker,
    IntakeWalker, MatchWalker, PledgeWalker, _my_person
}


def line(title: str) {
    print("");
    print("=== " + title + " " + "=" * max(0, 62 - len(title)));
}


with entry:__main__ {
    ensure_commons();
    # Sign up the way the Gate does when the location permission is granted:
    # what the browser hands back is a coordinate pair, not a ZIP.
    choose_role("seeker", "Maria", "email", "maria@example.com", "37.7749, -122.4194");

    line("Engine");
    rep = engine_report();
    print(f"mode      : {rep.mode}");
    print(f"model     : {rep.model}");
    if rep.reason {
        print(f"reason    : {rep.reason}");
    }
    if rep.mode != "llm" {
        print("");
        print("!! No working model connection -- there is no fallback, so nothing below will run.");
        print("!! export OPENAI_API_KEY (or ANTHROPIC_API_KEY / GOOGLE_API_KEY) and retry.");
        sys.exit(1);
    }

    line("IntakeWalker");
    # No ZIP in the story on purpose. The service area has to come from the
    # location granted at signup -- the agent is forbidden from asking for it
    # (core/question_guard.jac), so if that wire is broken the tier-1 broadcast
    # silently stops being filtered by area.
    intake = root spawn IntakeWalker(
        situation="I need food for me and my two kids this week. I lost my ID when we left the apartment, I don't have a car, and we're staying somewhere with no stove. We also got an eviction notice for the room we're in."
    );
    board = intake.reports[0];
    print("engine:", board.engine);
    print("headline:", board.headline);
    person = _my_person();
    if person is not None {
        area = person.zip_prefix if person.zip_prefix else "(none -- results NOT filtered by area)";
        print(f"service area resolved from location: {area}");
    }
    for step in board.steps {
        print(f"  [{step.status:9}] {step.title}");
        print(f"              {step.detail}");
        if step.blocker {
            print(f"              BLOCKER: {step.blocker}");
        }
    }
    print("anonymized needs on the commons:");
    for nd in board.needs {
        print(f"  {nd.code} {nd.category} urgency={nd.urgency} -> {nd.summary}");
    }
    # `audited` is printed separately from the leak list on purpose: an empty
    # list means "found nothing" only if the auditor actually ran, and reading
    # the two together is what makes that a claim rather than an assumption.
    if not board.privacy_audited {
        print("privacy auditor: DID NOT RUN -- nothing below has been checked");
    } elif board.privacy_leaks {
        print("privacy auditor: ran, caught and repaired before publishing:");
        for leak in board.privacy_leaks {
            print(f"  - {leak}");
        }
    } else {
        print("privacy auditor: ran, found no identity leaks in the published summary");
    }
    if board.answered {
        print("already answered:");
        for row in board.answered {
            print(f"  - {row}");
        }
    }

    line("StrategyWalker (the ReAct caseworker)");
    for brief in board.strategy {
        print(f"headline    : {brief.headline}");
        print(f"first action: {brief.first_action}");
        print("ordered plan:");
        for (i, action) in enumerate(brief.ordered_actions) {
            print(f"  {i + 1}. {action}");
        }
        print(f"community?  : {brief.rely_on_community}");
        print(f"risk        : {brief.risk}");
        print(f"note        : {brief.research_note}");
        print(f"open question: {brief.open_question if brief.open_question else '(none)'}");
        if brief.question_why {
            print(f"  because   : {brief.question_why}");
        }
        print("research path the agent CHOSE to take:");
        if brief.research_path {
            for call in brief.research_path {
                print(f"  - {call}");
            }
        } else {
            print("  (none -- the agent answered without consulting the graph this time)");
        }
    }

    line("AnswerWalker (answering the agent's question re-plans everything)");
    # The question is only worth asking if the answer moves the plan, so this
    # prints the plan on both sides of it. Answering does not tick a box: the
    # answer goes back into the person's own words and the whole chain -- intake,
    # every gate, the broadcast, the agent -- runs again on the enriched story.
    question = "";
    for brief in board.strategy {
        if brief.open_question {
            question = brief.open_question;
        }
    }
    if question {
        # Deliberately a plain "no" rather than an answer tailored to the exact
        # wording: the agent picks the question from whatever its research turned
        # up, so a canned reply here cannot presume which gate it landed on. Every
        # question it is allowed to ask is answerable this way.
        reply = "No -- I lost everything when we left, so I don't have that.";
        print(f"agent asked : {question}");
        print(f"answering   : {reply}");
        replan = root spawn AnswerWalker(answer=reply, question=question);
        board = replan.reports[0];

        print("");
        print("the plan, re-reasoned against that answer:");
        for step in board.steps {
            print(f"  [{step.status:9}] {step.title}");
        }
        print("what this person has told us, kept on the graph:");
        for row in board.answered {
            print(f"  - {row}");
        }
        for brief in board.strategy {
            print(f"fresh first action: {brief.first_action}");
            print(
                "asks again        : "
                + (brief.open_question if brief.open_question
                   else "(no -- the answered trail closed that line of questioning)")
            );
        }
    } else {
        print("the agent had no open question this time -- nothing its research");
        print("turned up hinged on something Maria had not already said.");
    }

    line("Matching without anyone asking for it");
    # Intake already published the needs -- and NeedBroadcastWalker woke the
    # matcher on each one as it landed. Whatever the seed pledges could cover is
    # therefore already matched, before the volunteer side has done anything.
    mid = root spawn CommunityBoard();
    print("after intake alone, with nobody having clicked anything:");
    for card in mid.reports[0].needs {
        print(f"  {card.code} {card.status:9} {card.matched_with if card.matched_with else '-'}");
    }

    line("PledgeWalker (the volunteer side) -- matches on arrival");
    orgs = mid.reports[0].orgs;
    pantry = [o for o in orgs if o.name == "Bayview Free Pantry"];
    pledged = root spawn PledgeWalker(
        kind="food",
        description="6 ready-to-eat family dinners, delivered, no cooking required",
        capacity=6,
        org_id=pantry[0].org_id,
        notes="I can drop these at the pantry or deliver."
    );
    print("pledge id:", pledged.reports[0]);
    print(f"matched on arrival: {pledged.matched_now} need(s) {pledged.matched_codes}");

    line("MatchWalker (manual sweep -- the backstop, not the mechanism)");
    matcher = root spawn MatchWalker();
    print(f"considered {matcher.considered} pairs, matched {matcher.matched}");
    print("(0 matched here is the CORRECT result -- the triggers already did it)");
    for note in matcher.notes {
        print("  passed:", note);
    }
    for card in matcher.reports {
        print(f"  {card.code} -> {card.matched_with}");
        print(f"     why: {card.match_rationale}");
    }

    line("FulfillmentWalker (back on the seeker's side)");
    fulfil = root spawn FulfillmentWalker();
    after = fulfil.reports[0];
    print("nudge:", after.nudge);
    for step in after.steps {
        print(f"  [{step.status:9}] {step.title}");
    }

    # Covering a category invalidates the brief the agent wrote when that
    # category was still open, so settling the match wakes the caseworker again.
    # Nobody asked for a re-plan: the graph event that made the old brief wrong
    # is the thing that ran the new one.
    print(f"caseworker re-planned on it: {fulfil.restrategized}");
    for brief in after.strategy {
        print(f"  fresh first action: {brief.first_action}");
        print(f"  reasoned over     : {len(brief.research_path)} graph lookup(s), post-fulfillment");
    }

    line("FollowUpWalker (48h later, nothing came back)");
    follow = root spawn FollowUpWalker(simulate_hours=48);
    print(f"escalated {follow.escalated} need(s), +{follow.fanout} org(s)");
    print(f"re-matched after the radius widened: {follow.rematched}");
    for card in follow.reports {
        print(f"  {card.code} tier={card.broadcast_tier} escalations={card.escalations} urgency={card.urgency}");
    }

    line("Walker activity log (shared graph state, in order)");
    final = root spawn CommunityBoard();
    view = final.reports[0];
    entries = view.activity;
    entries.reverse();
    for a in entries {
        print(f"  {a.walker:24} {a.detail}");
    }
    print("");
    print(f"open={view.open_count} matched={view.matched_count} fulfilled={view.fulfilled_count}");
}
