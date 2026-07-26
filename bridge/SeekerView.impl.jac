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
    answered = board.answered;
    privacy_leaks = board.privacy_leaks;
    engine_model = board.engine_model;
    engine_reason = board.engine_reason;
    engine_calls = board.engine_calls;
    engine_roles = board.engine_roles;
}


impl SeekerView.refresh -> None {
    try {
        result = await root spawn FulfillmentWalker();
        if result.reports and len(result.reports) > 0 {
            board = result.reports[0];
            apply(board);
            # Hold the box in sync with the graph whenever it is not being
            # edited, so re-describing always opens on the words that produced
            # the plan on screen -- and so backing out discards the edit. While
            # `editing`, the box is the person's; the poll keeps its hands off.
            # `board.situation` is empty until a Person exists, which is what
            # stops this from wiping what someone is typing before their first
            # submit.
            if board.situation and not editing {
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
            # IntakeWalker takes the update path itself -- one Person, replanned,
            # stale needs retired -- so a successful resubmit just closes the box.
            editing = False;
        }
    } except Exception as e {
        raw = str(e);
        if "ENGINE_UNAVAILABLE" in raw {
            error = "Bridge has no working model connection right now, so a plan can't be built. Add an API key on the server and try again.";
        } else {
            error = "Something went wrong building the plan. Try again in a moment.";
        }
    }
    busy = False;
}


"""Send the answer to the agent's question and let the pipeline re-plan on it.

The whole chain re-runs server-side, so this is a slow call by design -- what
comes back is a plan that was re-reasoned against the new fact, not the old plan
with a field filled in.
"""
impl SeekerView.send_answer(value: str) -> None {
    reply = value.strip();
    if not reply or answering {
        return;
    }
    answering = True;
    error = "";
    question = "";
    for brief in strategy {
        if brief.open_question {
            question = brief.open_question;
        }
    }
    try {
        result = await root spawn AnswerWalker(answer=reply, question=question);
        if result.reports and len(result.reports) > 0 {
            apply(result.reports[0]);
        }
        answer_draft = "";
    } except Exception as e {
        error = "Could not record that answer: " + str(e);
    }
    answering = False;
}


impl SeekerView.set_draft(value: str) -> None {
    answer_draft = value;
}


impl SeekerView.use_example(e: MouseEvent) -> None {
    situation = EXAMPLE;
}


"""Reopen intake over an existing plan, pre-filled with what they said last time."""
impl SeekerView.start_over(e: MouseEvent) -> None {
    editing = True;
    error = "";
}


"""Back out of a re-describe. Nothing was sent, so the plan is untouched."""
impl SeekerView.keep_plan(e: MouseEvent) -> None {
    editing = False;
    error = "";
}
