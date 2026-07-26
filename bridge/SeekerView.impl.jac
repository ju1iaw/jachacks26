"""Handlers for SeekerView."""

def _ref_ids(ref: Ref[list[str]]) -> list[str] {
    cur = ref.current;
    return cur if cur else [];
}


def _ref_sugs(ref: Ref[list[Suggestion]]) -> list[Suggestion] {
    cur = ref.current;
    return cur if cur else [];
}


impl SeekerView.apply(board: SeekerBoard) -> int {
    nudge = board.nudge;
    strategy = board.strategy;
    answered = board.answered;
    privacy_leaks = board.privacy_leaks;
    activity = board.activity;
    engine = board.engine;
    engine_model = board.engine_model;
    engine_reason = board.engine_reason;
    engine_calls = board.engine_calls;
    engine_roles = board.engine_roles;

    # The question comes off the agent's brief rather than a role of its own, so
    # it is only ever asked when the research that justifies it found something.
    # Skip while an answer is in flight so the 3s poll cannot restore the card.
    answering = True if answering_ref.current else False;
    if not answering {
        asked = "";
        why = "";
        for brief in board.strategy {
            if brief.open_question {
                asked = brief.open_question;
                why = brief.question_why;
            }
        }
        clarify_question = asked;
        clarify_why = why;
    }

    if board.situation and not situation {
        situation = board.situation;
    }

    handled = _ref_ids(handled_ref);
    next_ongoing = _ref_sugs(ongoing_ref);

    candidates = board_to_suggestions(board.steps);
    next_inbox: list[Suggestion] = [];
    for sug in candidates {
        if sug.id in handled {
            continue;
        }
        next_inbox = next_inbox + [sug];
    }

    # Unconfirmed helper matches belong under Ongoing (unless already handled).
    for card in board.needs {
        if card.status != "matched" {
            continue;
        }
        sug = need_to_suggestion(card);
        if sug.id in handled {
            continue;
        }
        already = False;
        for o in next_ongoing {
            if o.id == sug.id {
                already = True;
                break;
            }
        }
        if not already {
            next_ongoing = next_ongoing + [sug];
            handled = handled + [sug.id];
        }
    }

    handled_ref.current = handled;
    ongoing_ref.current = next_ongoing;
    inbox = next_inbox;
    ongoing = next_ongoing;
    past = _ref_sugs(past_ref);
    return len(next_inbox);
}


impl SeekerView.refresh -> None {
    try {
        result = await root spawn FulfillmentWalker();
        if result.reports and len(result.reports) > 0 {
            apply(result.reports[0]);
        }
    } except Exception {
        nudge = nudge;
    }
}


impl SeekerView.submit -> None {
    await submit_with(situation);
}


impl SeekerView.submit_with(text: str) -> None {
    request = text.strip();
    if not request {
        error = "Tell us what you need first.";
        return;
    }
    situation = request;
    busy = True;
    error = "";
    inbox_len: int = 0;
    try {
        result = await root spawn IntakeWalker(situation=request);
        if result.reports and len(result.reports) > 0 {
            inbox_len = apply(result.reports[0]);
        }
    } except Exception as e {
        raw = str(e);
        if "ENGINE_UNAVAILABLE" in raw {
            error = "No model connection right now — showing example programs you can try.";
        } else {
            error = "Something went wrong — showing example programs you can try.";
        }
    }

    if inbox_len == 0 {
        handled = _ref_ids(handled_ref);
        next_inbox: list[Suggestion] = [];
        for d in demo_suggestions() {
            if d.id not in handled {
                next_inbox = next_inbox + [d];
            }
        }
        inbox = next_inbox;
    }
    busy = False;
}


impl SeekerView.use_example(e: MouseEvent) -> None {
    situation = EXAMPLE;
}


impl SeekerView.accept_item(sid: str) -> None {
    moved: list[Suggestion] = [s for s in inbox if s.id == sid];
    inbox = [s for s in inbox if s.id != sid];
    if len(moved) == 0 {
        return;
    }
    handled = _ref_ids(handled_ref);
    if sid not in handled {
        handled = handled + [sid];
    }
    handled_ref.current = handled;

    next_ongoing = _ref_sugs(ongoing_ref) + moved;
    ongoing_ref.current = next_ongoing;
    ongoing = next_ongoing;
    ongoing_open = True;
}


impl SeekerView.dismiss_item(sid: str) -> None {
    moved: list[Suggestion] = [s for s in inbox if s.id == sid];
    inbox = [s for s in inbox if s.id != sid];
    if len(moved) == 0 {
        return;
    }
    handled = _ref_ids(handled_ref);
    if sid not in handled {
        handled = handled + [sid];
    }
    handled_ref.current = handled;

    next_past = _ref_sugs(past_ref) + moved;
    past_ref.current = next_past;
    past = next_past;
}


impl SeekerView.dismiss_ongoing(sid: str) -> None {
    cur = _ref_sugs(ongoing_ref);
    moved: list[Suggestion] = [s for s in cur if s.id == sid];
    next_ongoing = [s for s in cur if s.id != sid];
    ongoing_ref.current = next_ongoing;
    ongoing = next_ongoing;
    if len(moved) == 0 {
        return;
    }
    handled = _ref_ids(handled_ref);
    if sid not in handled {
        handled = handled + [sid];
    }
    handled_ref.current = handled;

    next_past = _ref_sugs(past_ref) + moved;
    past_ref.current = next_past;
    past = next_past;
}


impl SeekerView.toggle_ongoing -> None {
    ongoing_open = not ongoing_open;
}


impl SeekerView.go_home(e: MouseEvent) -> None {
    if onHome {
        onHome();
    }
}


impl SeekerView.set_clarify_reply(e: ChangeEvent) -> None {
    clarify_reply = e.target.value;
}


impl SeekerView.answer_clarify_yes(e: MouseEvent) -> None {
    # Plain "Yes" -- AnswerWalker stores the question alongside it and folds both
    # into the narrative, so echoing the question back here would duplicate it.
    await apply_clarify("Yes");
}


impl SeekerView.answer_clarify_no(e: MouseEvent) -> None {
    await apply_clarify("No");
}


impl SeekerView.send_clarify_reply -> None {
    await apply_clarify(clarify_reply);
}


"""Answer the agent's question and let the whole pipeline re-reason on it.

Deliberately NOT a resubmit with the answer glued onto the situation. `AnswerWalker`
records the Q&A as a node, folds it into the person's own words and re-runs the
chain -- so the answer lands in the trail the agent is handed on every re-plan,
which is what stops it being asked twice. Slow by design: what comes back is a
plan re-reasoned against the new fact, not the old plan with a field filled in.
"""
impl SeekerView.apply_clarify(ans: str) -> None {
    text = ans.strip();
    if not text or answering {
        return;
    }
    asked = clarify_question;
    answering = True;
    answering_ref.current = True;
    error = "";
    # Close the card straight away -- the re-plan takes a few seconds and the
    # question it was asking has already been answered.
    clarify_reply = "";
    clarify_question = "";
    clarify_why = "";
    try {
        result = await root spawn AnswerWalker(answer=text, question=asked);
        if result.reports and len(result.reports) > 0 {
            apply(result.reports[0]);
        }
    } except Exception as e {
        raw = str(e);
        if "ENGINE_UNAVAILABLE" in raw {
            error = "No model connection right now, so that answer could not be worked through.";
        } else {
            error = "Could not record that answer. Try again in a moment.";
        }
    }
    answering_ref.current = False;
    answering = False;
}


impl SeekerView.open_settings_form -> None {
    draft_name = display_name;
    draft_email = email;
    draft_phone = phone;
    draft_location = location;
    draft_notes = eligibility_notes;
    settings_msg = "";
    settings_err = "";
    try {
        account = await me();
        if account is not None {
            draft_name = account.display_name if account.display_name else draft_name;
            draft_email = account.email if account.email else draft_email;
            draft_phone = account.phone if account.phone else draft_phone;
            draft_location = account.location if account.location else draft_location;
            draft_notes = account.eligibility_notes if account.eligibility_notes else draft_notes;
        }
    } except Exception {
        # Props are enough to edit offline of a failed refresh.
        settings_err = "";
    }
}


impl SeekerView.save_settings -> None {
    if not draft_name.strip() {
        settings_err = "Name can’t be empty.";
        settings_msg = "";
        return;
    }
    settings_busy = True;
    settings_err = "";
    settings_msg = "";
    try {
        _ = await update_profile(
            draft_name.strip(),
            draft_email.strip(),
            draft_phone.strip(),
            draft_location.strip(),
            draft_notes
        );
        settings_msg = "Saved.";
        if onProfileSaved {
            onProfileSaved();
        }
    } except Exception as e {
        settings_err = "Could not save: " + str(e);
    }
    settings_busy = False;
}


impl SeekerView.set_draft_name(e: ChangeEvent) -> None {
    draft_name = e.target.value;
}


impl SeekerView.set_draft_email(e: ChangeEvent) -> None {
    draft_email = e.target.value;
}


impl SeekerView.set_draft_phone(e: ChangeEvent) -> None {
    draft_phone = e.target.value;
}


impl SeekerView.set_draft_location(e: ChangeEvent) -> None {
    draft_location = e.target.value;
}


impl SeekerView.set_draft_notes(e: ChangeEvent) -> None {
    draft_notes = e.target.value;
}
