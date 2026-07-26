"""End-to-end smoke run of the whole Bridge walker chain on one local graph.

    jac run scripts/smoke.jac

Under `jac run` there is one root and `root.shared is root`, so both "users"
share a graph -- fine for exercising the walkers, but the real per-user
isolation only shows up under `jac start`. See scripts/demo_flow.sh for that.
"""

import from core.commons { choose_role, ensure_commons }
import from core.walkers {
    CommunityBoard, EligibilityPathWalker, FollowUpWalker, FulfillmentWalker,
    IntakeWalker, MatchWalker, NeedBroadcastWalker, PledgeWalker
}


def line(title: str) {
    print("");
    print("=== " + title + " " + "=" * max(0, 62 - len(title)));
}


with entry:__main__ {
    ensure_commons();
    choose_role("seeker", "Maria");

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
