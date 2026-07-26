"""End-to-end smoke run of the whole Bridge walker chain on one local graph.

    jac run scripts/smoke.jac

Under `jac run` there is one root and `root.shared is root`, so both "users"
share a graph -- fine for exercising the walkers, but the real per-user
isolation only shows up under `jac start`. See scripts/demo_flow.sh for that.
"""

import from core.commons { choose_role, ensure_commons, engine_report }
import from core.walkers {
    CommunityBoard, EligibilityPathWalker, FollowUpWalker, FulfillmentWalker,
    IntakeWalker, MatchWalker, NeedBroadcastWalker, PledgeWalker, StrategyWalker
}


def line(title: str) {
    print("");
    print("=== " + title + " " + "=" * max(0, 62 - len(title)));
}


with entry:__main__ {
    ensure_commons();
    choose_role("seeker", "Maria");

    line("Engine");
    rep = engine_report();
    print(f"mode      : {rep.mode}");
    print(f"model     : {rep.model}");
    if rep.reason {
        print(f"reason    : {rep.reason}");
    }
    if rep.mode != "llm" {
        print("!! byLLM is NOT answering -- every judgement below is a deterministic fallback.");
        print("!! export OPENAI_API_KEY to switch the real reasoning on.");
    }

    line("IntakeWalker");
    intake = root spawn IntakeWalker(
        situation="I need food for me and my two kids this week. I lost my ID when we left the apartment, I don't have a car, and we're staying somewhere with no stove. Zip is 94110."
    );
    board = intake.reports[0];
    print("engine:", board.engine);
    print("headline:", board.headline);
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
    if board.privacy_leaks {
        print("privacy auditor caught and repaired before publishing:");
        for leak in board.privacy_leaks {
            print(f"  - {leak}");
        }
    } else {
        print("privacy auditor: no identity leaks in the published summary");
    }
    if board.clarify_question {
        print(f"clarifying question: {board.clarify_question}");
        print(f"               why: {board.clarify_why}");
    }

    line("StrategyWalker (the ReAct caseworker)");
    for sv in board.strategy {
        print(f"headline    : {sv.headline}");
        print(f"first action: {sv.first_action}");
        print("ordered plan:");
        for (i, action) in enumerate(sv.ordered_actions) {
            print(f"  {i + 1}. {action}");
        }
        print(f"community?  : {sv.rely_on_community}");
        print(f"risk        : {sv.risk}");
        print(f"note        : {sv.research_note}");
        print("research path the agent CHOSE to take:");
        if sv.research_path {
            for call in sv.research_path {
                print(f"  - {call}");
            }
        } else {
            print("  (none -- the fallback planner does no research)");
        }
    }

    line("PledgeWalker (the volunteer side)");
    cb = root spawn CommunityBoard();
    orgs = cb.reports[0].orgs;
    pantry = [o for o in orgs if o.name == "Bayview Free Pantry"];
    pledged = root spawn PledgeWalker(
        kind="food",
        description="6 ready-to-eat family dinners, delivered, no cooking required",
        capacity=6,
        org_id=pantry[0].org_id,
        notes="I can drop these at the pantry or deliver."
    );
    print("pledge id:", pledged.reports[0]);

    line("MatchWalker");
    matcher = root spawn MatchWalker();
    print(f"considered {matcher.considered} pairs, matched {matcher.matched}");
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

    line("FollowUpWalker (48h later, nothing came back)");
    follow = root spawn FollowUpWalker(simulate_hours=48);
    print(f"escalated {follow.escalated} need(s), +{follow.fanout} org(s)");
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
