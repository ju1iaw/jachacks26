"""Tests for the guard on what the caseworker agent may ask.

    jac test core/question_guard.jac

`open_question` is the one thing the agent says that is addressed *to* the person
rather than about their plan, and the rules governing it are lines in a prompt.
The agent has been observed ignoring two of them, so `unfit_question` is the
deterministic backstop and these are its regression tests. Both offenders below
are verbatim from real runs against gpt-4o-mini with the rule forbidding them
already in the prompt.

The false-positive cases matter as much as the true positives, because the guard
drops whatever it flags. Two distinctions carry that weight:

  * **a value vs a document** -- "what is your address?" collects an identifying
    detail; "do you have mail showing your address?" asks about a piece of paper
    they either have or do not. Both mention an address; the opener separates them.
  * **their own life vs the agent's research** -- "do you have a shelter letter?"
    is answerable from what they know; "how will you obtain proof of address?"
    asks them to solve the problem they came here with.
"""


# This is a `.test.jac` annex of core/question_guard.jac -- everything in that
# module is already in scope, and importing it again is a circular import.


test "the observed address-seeking question is caught" {
    caught = unfit_question(
        "What is the current address or location where the person is staying?"
    );
    assert caught == "for their address";
}


test "the observed research-offloading question is caught" {
    caught = unfit_question("How will you obtain proof of address for food assistance?");
    assert caught == "to do the research it has tools for";
}


test "a bare where-question is caught whatever follows it" {
    assert unfit_question("Where are you staying tonight?") == "for their location";
    assert unfit_question("Where do you live?") == "for their location";
}


test "value-demanding openers over an identifying detail are caught" {
    assert unfit_question("What is your phone number?") == "for their phone number";
    assert unfit_question("What's your full name?") == "for their name";
    assert unfit_question("Who is your employer?") == "for their employer";
    assert unfit_question("Which school do your kids attend?") == "for their school";
}


test "other ways of handing the research back are caught" {
    offloads = [
        "How would you get a copy of the eviction notice?",
        "How do you plan to book the intake appointment?",
        "How are you going to reach the DMV without a car?",
        "What is the best way for you to prove residency?"
    ];
    for q in offloads {
        assert unfit_question(q) != "", f"should have been withheld: {q}";
    }
}


test "asking whether they HAVE a document survives" {
    # These all mention an identifying detail and must all survive: each one is a
    # yes/no about paperwork tied to a real gate in the seed graph, which is
    # precisely the question the agent is supposed to be asking.
    assert unfit_question("Do you have any mail showing your address?") == "";
    assert unfit_question("Can you get a letter from where you are staying?") == "";
    assert unfit_question("Is there a phone number they could reach you on?") == "";
    assert unfit_question("Do you have any photo ID, even an expired one?") == "";
}


test "a clean question about a gate is left alone" {
    assert unfit_question("Do you have a copy of the eviction notice?") == "";
    assert unfit_question("Can you call the access line at 8am?") == "";
    assert unfit_question("Do you have a shelter or clinic letter for the DMV?") == "";
}


test "a how-question that is not offloading research survives" {
    # "how" alone must not be a trip-wire: this one is answerable from their own
    # life and bears on family-shelter eligibility.
    assert unfit_question("How old are your children?") == "";
}


test "the guard is not confused by whitespace or casing" {
    assert unfit_question("  WHAT   IS   YOUR   ADDRESS?  ") == "for their address";
}


test "the reason reads as a sentence in the activity feed" {
    # The caller logs "the agent tried to ask this person <reason>", so every
    # reason has to slot in grammatically or the trace reads as gibberish.
    reasons = [
        unfit_question("What is your address?"),
        unfit_question("Where are you staying?"),
        unfit_question("How will you obtain a photo ID?")
    ];
    for reason in reasons {
        assert reason.startswith("for ") or reason.startswith("to ");
    }
}
