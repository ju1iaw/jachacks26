"""Handlers for HelperView."""

def clean_error(prefix: str, raw: str) -> str {
    if "ENGINE_UNAVAILABLE" in raw {
        return "Bridge has no working model connection right now. Add an API key on the server and try again.";
    }
    return prefix + " Try again in a moment.";
}


impl HelperView.refresh -> None {
    try {
        result = await root spawn CommunityBoard();
        if result.reports and len(result.reports) > 0 {
            view = result.reports[0];
            needs = view.needs;
            pledges = view.pledges;
            orgs = view.orgs;
            activity = view.activity;
            open_count = view.open_count;
            matched_count = view.matched_count;
            fulfilled_count = view.fulfilled_count;
            engine = view.engine;
            engine_model = view.engine_model;
            engine_reason = view.engine_reason;
            engine_calls = view.engine_calls;
            engine_roles = view.engine_roles;
            if not org_id and len(view.orgs) > 0 {
                org_id = view.orgs[0].org_id;
            }
        }
    } except Exception {
        engine = engine;
    }
}


impl HelperView.add_pledge -> None {
    if not description.strip() or not org_id {
        flash = "Describe the pledge and pick an org to route it through.";
        return;
    }
    busy = "pledge";
    units: int = 1;
    try {
        units = int(capacity);
    } except Exception {
        units = 1;
    }
    try {
        # PledgeWalker wakes the matcher itself, so by the time this returns the
        # matching has already happened -- `matched_now` is what it did, read off
        # the walker rather than out of `reports` (a nested spawn's reports go to
        # the outer stream, so MatchWalker runs with emit=False in there).
        result = await root spawn PledgeWalker(
            kind=kind,
            description=description,
            capacity=units,
            org_id=org_id,
            notes=notes
        );
        hit = result.matched_now;
        flash = (
            "On the shelf - and it already matched " + str(hit) + " open need(s)."
            if hit > 0
            else "On the shelf. Nothing open fits it right now; it'll be reconsidered the moment something does."
        );
        description = "";
        notes = "";
    } except Exception as e {
        flash = clean_error("Could not add that.", str(e));
    }
    busy = "";
    await refresh();
}


"""A manual full sweep of the commons.

Matching is autonomous -- needs and pledges each wake the matcher as they land,
so this button is a backstop, not the mechanism. It exists for the case where a
match attempt was lost to a provider blip (those are logged in the feed and the
need stays open), and for re-checking every open need at once after the shelf
has changed. On a healthy graph it should find nothing left to do.
"""
impl HelperView.run_match -> None {
    busy = "match";
    try {
        result = await root spawn MatchWalker();
        made = len(result.reports) if result.reports else 0;
        flash = (
            "Swept the commons - matched " + str(made) + " need(s) the triggers had missed."
            if made > 0
            else "Swept every open need - nothing left for it to do."
        );
    } except Exception as e {
        flash = clean_error("Matcher failed.", str(e));
    }
    busy = "";
    await refresh();
}


impl HelperView.run_followup -> None {
    busy = "follow";
    try {
        result = await root spawn FollowUpWalker(simulate_hours=48);
        made = len(result.reports) if result.reports else 0;
        flash = (
            "Escalated " + str(made) + " unfilled need(s) to a wider radius."
            if made > 0
            else "Nothing has been sitting unfilled long enough to escalate."
        );
    } except Exception as e {
        flash = clean_error("Follow-up failed.", str(e));
    }
    busy = "";
    await refresh();
}
