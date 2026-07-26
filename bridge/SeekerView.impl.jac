"""Handlers for SeekerView."""

impl SeekerView.apply(board: SeekerBoard) -> None {
    steps = board.steps;
    needs = board.needs;
    activity = board.activity;
    headline = board.headline;
    nudge = board.nudge;
    engine = board.engine;
    has_plan = board.has_plan;
    strategy = board.strategy;
    clarify_question = board.clarify_question;
    clarify_why = board.clarify_why;
    privacy_leaks = board.privacy_leaks;
    engine_model = board.engine_model;
    engine_reason = board.engine_reason;
    engine_calls = board.engine_calls;
    engine_fallbacks = board.engine_fallbacks;
    engine_roles = board.engine_roles;
}


impl SeekerView.refresh -> None {
    try {
        result = await root spawn FulfillmentWalker();
        if result.reports and len(result.reports) > 0 {
            board = result.reports[0];
            apply(board);
            if board.situation and not situation {
                situation = board.situation;
            }
        }
    } except Exception {
        # A poll that fails is not worth surfacing - the next tick retries.
        engine = engine;
    }
}


impl SeekerView.submit -> None {
    if not situation.strip() {
        error = "Tell us what's going on first.";
        return;
    }
    busy = True;
    error = "";
    try {
        result = await root spawn IntakeWalker(situation=situation);
        if result.reports and len(result.reports) > 0 {
            apply(result.reports[0]);
        }
    } except Exception as e {
        error = "Something went wrong building the plan: " + str(e);
    }
    busy = False;
}


impl SeekerView.use_example(e: MouseEvent) -> None {
    situation = EXAMPLE;
}
