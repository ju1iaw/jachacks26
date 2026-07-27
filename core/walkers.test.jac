"""Tests for the walkers.

    jac test core/walkers.test.jac

Covers the part of re-intake that has no other safety net: what happens to a
donor's pledge when the need it was matched to is retired.

Re-describing your situation deletes your old `Need` nodes so the commons never
carries two live asks for the same household. A matched need has already taken
units off a `Contribution`, and deleting the node takes the `Matched` edge --
the only record of how many -- away with it. Miss the credit and the shelf
drains a few units on every re-describe, until the matcher starts reporting that
nothing fits against pledges nobody ever used. That failure is silent and it
looks exactly like a bad match, so it gets a test.

These need no model: `release_pledge` is pure graph work.
"""


# This is a `.test.jac` annex of core/walkers.jac -- everything in that module,
# and everything it imports, is already in scope.


"""A pledge on the shelf with `capacity - remaining` units already spoken for."""
def _pledge(capacity: int, remaining: int) -> Contribution {
    return root ++> Contribution(
        kind="food",
        description="12 ready-to-eat family meal boxes, no cooking needed",
        capacity=capacity,
        remaining=remaining,
        notes="Dropped at the pantry every Wednesday."
    );
}


def _need(status: str) -> Need {
    made = root ++> Need(
        category="food",
        summary="Needs groceries. Household of 3; no way to cook.",
        urgency="critical",
        zip_prefix="941",
        household=3,
        status=status,
        created_at=now_iso()
    );
    made.code = "N-TEST";
    return made;
}


"""Attach the edge MatchWalker would have written, taking `units` off the pledge."""
def _match(need: Need, pledge: Contribution, units: int) {
    need +>:Matched(
        pledge_desc=pledge.description,
        rationale="Ready to eat, no cooking needed -- fits a household with no stove.",
        units=units,
        score=94,
        engine="test",
        at=now_iso()
    ):+> pledge;
    pledge.remaining = pledge.remaining - units;
    need.status = "matched";
}


# ===========================================================================
# Retiring a need puts the donor's units back
# ===========================================================================

test "retiring a matched need returns its units to the donor's pledge" {
    pledge = _pledge(capacity=12, remaining=12);
    need = _need("open");
    _match(need, pledge, 4);
    assert pledge.remaining == 8;

    IntakeWalker(situation="unused").release_pledge(need);

    # Back to a full shelf: the need that was holding those 4 is being retired.
    assert pledge.remaining == 12;
}


test "a second re-describe does not drain the shelf a second time" {
    # The regression this whole helper exists for. Two rounds of match-then-
    # retire must leave the pledge exactly where it started, not 8 units down.
    pledge = _pledge(capacity=12, remaining=12);

    for _ in range(2) {
        need = _need("open");
        _match(need, pledge, 4);
        IntakeWalker(situation="unused").release_pledge(need);
        del need;
    }

    assert pledge.remaining == 12;
}


test "the credit is capped at what the donor actually pledged" {
    # A pledge that was topped up after the match must not be inflated past its
    # own capacity by giving back units against the larger number.
    pledge = _pledge(capacity=12, remaining=12);
    need = _need("open");
    _match(need, pledge, 5);
    pledge.remaining = 12;

    IntakeWalker(situation="unused").release_pledge(need);

    assert pledge.remaining == 12;
}


test "retiring an unmatched need leaves every pledge alone" {
    pledge = _pledge(capacity=12, remaining=7);
    need = _need("open");

    IntakeWalker(situation="unused").release_pledge(need);

    assert pledge.remaining == 7;
}


test "a matched need's units are read off the edge, not guessed" {
    # Two needs against one pledge, different sizes. Retiring the smaller one
    # must return 2, not the other need's 6 and not some average.
    pledge = _pledge(capacity=12, remaining=12);
    small = _need("open");
    big = _need("open");
    _match(small, pledge, 2);
    _match(big, pledge, 6);
    assert pledge.remaining == 4;

    IntakeWalker(situation="unused").release_pledge(small);

    assert pledge.remaining == 6;
}


test "a volunteered detail is not recorded as the answer to a question" {
    # `answered_trail` is handed to the caseworker as `already_answered`, whose
    # prompt says to treat every line as established fact. Pairing a bare "No"
    # with a fabricated question gives the model a negation with no referent.
    person = root ++> Person(alias="p", situation="needs food", created_at=now_iso());
    person +>:HasAnswer:+> AnsweredQuestion(
        question="",
        answer="No -- I lost everything when we left.",
        at=now_iso()
    );

    trail = answered_trail(person);

    assert len(trail) == 1;
    assert "unprompted detail" not in trail[0];
    assert trail[0].startswith("(volunteered, unprompted)");
    assert "No -- I lost everything when we left." in trail[0];
}


test "a real question still reads as a question and answer pair" {
    person = root ++> Person(alias="p", situation="needs food", created_at=now_iso());
    person +>:HasAnswer:+> AnsweredQuestion(
        question="Do you have a shelter letter?",
        answer="No.",
        at=now_iso()
    );

    trail = answered_trail(person);

    assert trail[0] == "Do you have a shelter letter? -> No.";
}
