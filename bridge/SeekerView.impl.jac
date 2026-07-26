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
    clarify_question = board.clarify_question;
    clarify_why = board.clarify_why;

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
    await apply_clarify("Yes — " + clarify_question);
}


impl SeekerView.answer_clarify_no(e: MouseEvent) -> None {
    await apply_clarify("No — " + clarify_question);
}


impl SeekerView.send_clarify_reply -> None {
    await apply_clarify(clarify_reply);
}


impl SeekerView.apply_clarify(ans: str) -> None {
    text = ans.strip();
    if not text {
        return;
    }
    base = situation;
    combined = (base + " Additional detail: " + text) if base.strip() else text;
    situation = combined;
    clarify_reply = "";
    clarify_question = "";
    clarify_why = "";
    await submit_with(combined);
}
