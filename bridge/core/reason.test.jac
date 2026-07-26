"""Tests for the reasoning layer.

    jac test core/reason.test.jac

The parallel-launch tests are the important ones: `flow` inside a comprehension
captures the loop variable by reference, so a future built inline reads whatever
the last iteration left behind. That produced a real bug -- every eligibility
gate on an org got the LAST gate's verdict, which silently turned blocked orgs
into "you qualify". The `launch_*` wrappers exist to prevent it, and these tests
are what stop someone inlining them again.
"""


# This is a `.test.jac` annex of core/reason.jac -- everything in that module is
# already in scope, and importing it again is a circular import.


test "intake extracts household, constraints and an anonymized summary" {
    read = heuristic_read(
        "I need food for me and my two kids this week. I lost my ID, "
        "I don't have a car, and where we're staying has no stove. Zip is 94110."
    );
    assert read.household == 3;
    assert "food" in read.categories;
    assert read.zip_prefix == "941";
    assert "no way to cook" in read.anonymized_summary;
    assert "no photo ID" in read.anonymized_summary;
}


test "the anonymized summary carries nothing identifying" {
    read = heuristic_read(
        "My name is Maria Alvarez, I live at 1420 Shotwell St and my number "
        "is 415-555-0199. I need food for my two kids. Zip 94110."
    );
    low = read.anonymized_summary.lower();
    for leak in ["maria", "alvarez", "shotwell", "555", "94110"] {
        assert leak not in low;
    }
}


test "an unmet document gate blocks and carries a workaround" {
    verdict = heuristic_requirement(
        "I lost my ID when we left the apartment.",
        "nothing confirmed",
        "Government-issued photo ID",
        "document",
        "Get a free California ID at the DMV on Fell St."
    );
    assert not verdict.satisfied;
    assert "DMV" in verdict.unblock_action;
}


test "a gate the person already clears does not block" {
    verdict = heuristic_requirement(
        "I have my state photo ID with me.",
        "state photo ID",
        "Government-issued photo ID",
        "document",
        ""
    );
    assert verdict.satisfied;
    assert verdict.unblock_action == "";
}


test "matching reasons about usability, not just category" {
    unusable = heuristic_match(
        "Needs groceries. Household of 3; no way to cook.",
        "food", 3, "food", "40lb of dry rice, beans and pasta", "Pickup only.", 8
    );
    assert not unusable.fits;

    usable = heuristic_match(
        "Needs groceries. Household of 3; no way to cook.",
        "food", 3, "food", "12 ready-to-eat family meal boxes", "Can be delivered.", 12
    );
    assert usable.fits;
    assert usable.score > unusable.score;
    assert usable.units <= 12;
}


test "a depleted pledge is never offered again" {
    verdict = heuristic_match(
        "Needs groceries. Household of 2.",
        "food", 2, "food", "meal boxes", "", 0
    );
    assert not verdict.fits;
    assert verdict.units == 0;
}


test "parallel gate judgements stay aligned with their gates" {
    gates = [
        ["Government-issued photo ID", "document", "Visit the DMV."],
        ["Household income under 125% FPL", "income", ""],
        ["Intake appointment booked in advance", "appointment", "Call at 8am."]
    ];
    pending = [
        launch_requirement("I lost my ID.", "nothing confirmed", g[0], g[1], g[2])
        for g in gates
    ];
    verdicts: list[EligibilityVerdict] = [wait f for f in pending];

    assert len(verdicts) == 3;
    # document gate -> unmet, income -> self-attested, appointment -> must book.
    # If `flow` late-bound the loop variable these would all be identical.
    assert not verdicts[0].satisfied;
    assert verdicts[1].satisfied;
    assert not verdicts[2].satisfied;
    assert "DMV" in verdicts[0].unblock_action;
    assert "8am" in verdicts[2].unblock_action;
}


test "parallel match judgements stay aligned with their pledges" {
    pledges = [
        ["40lb of dry rice, beans and pasta", "Pickup only."],
        ["12 ready-to-eat family meal boxes", "Can be delivered."]
    ];
    pending = [
        launch_match(
            "Needs groceries. Household of 3; no way to cook.",
            "food", 3, "food", p[0], p[1], 10
        )
        for p in pledges
    ];
    verdicts: list[MatchVerdict] = [wait f for f in pending];

    assert len(verdicts) == 2;
    assert not verdicts[0].fits;   # needs cooking
    assert verdicts[1].fits;       # ready to eat
}
