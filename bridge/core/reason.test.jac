"""Tests for the reasoning layer.

    jac test core/reason.test.jac

Three groups:

  * **`by llm()` path** -- swap the module's `llm` glob for a `MockLLM` and run
    the real `by llm()`-bodied functions. These prove the structured-output
    contract (schema injection, typed parse, unit clamping) without a network
    call. If a `sem` or a return `obj` drifts, these fail.
  * **Engine honesty** -- the state machine that decides whether the model or the
    fallback is answering, and that a fallback is never silent.
  * **Fallback behaviour** -- the deterministic path, including the tie-break bug
    that used to greet a food emergency with "let's get you a safe place to stay".

The parallel-launch tests are the subtle ones: `flow` inside a comprehension
captures the loop variable by reference, so a future built inline reads whatever
the last iteration left behind. That produced a real bug -- every eligibility
gate on an org got the LAST gate's verdict, which silently turned blocked orgs
into "you qualify". The `launch_*` wrappers exist to prevent it, and these tests
are what stop someone inlining them again.
"""


# This is a `.test.jac` annex of core/reason.jac -- everything in that module is
# already in scope, and importing it again is a circular import.

import from jaclang.byllm.lib { MockLLM }


"""Point the module's `llm` glob at a MockLLM and force the engine to 'live'.

`llm` is a real `glob` in reason.jac precisely so this is possible: the
`by llm()` bodies resolve it at call time, so rebinding it here makes the actual
LLM code path run against scripted structured outputs. Forcing `ENGINE` avoids a
preflight network call.
"""
def _use_mock(outputs: list) {
    llm = MockLLM(model_name="mockllm", config={"outputs": outputs});
    ENGINE.checked = True;
    ENGINE.mode = "llm";
    ENGINE.reason = "";
}


def _reset_engine {
    ENGINE.checked = False;
    ENGINE.mode = "unknown";
    ENGINE.calls = 0;
    ENGINE.failures = 0;
    ENGINE.fallbacks = 0;
    DEGRADE_LOG.clear();
    ROLE_CALLS.clear();
}


# ===========================================================================
# The by llm() path, under MockLLM
# ===========================================================================

test "read_situation runs through by llm() and returns a typed SituationRead" {
    _reset_engine();
    _use_mock([
        SituationRead(
            categories=["food"],
            urgency="critical",
            household=3,
            zip_prefix="941",
            assets=[],
            anonymized_summary="Household of 3; no transport, no way to cook.",
            headline="Let's get you food today."
        )
    ]);

    read = read_situation_safe("I need food for my two kids, no car, no stove, 94110");

    assert read.urgency == "critical";
    assert read.household == 3;
    assert read.categories == ["food"];
    # The LLM path really ran: the call was counted and nothing fell back.
    assert ROLE_CALLS.get("read_situation", 0) == 1;
    assert ENGINE.fallbacks == 0;
    _reset_engine();
}


test "the privacy auditor's repaired summary is what gets returned" {
    _reset_engine();
    _use_mock([
        LeakAudit(
            safe=False,
            leaks=["name: Maria", "street address: 1420 Shotwell St"],
            repaired_summary="Household of 3; no transport, no photo ID."
        )
    ]);

    audit = audit_anonymization_safe(
        "My name is Maria at 1420 Shotwell St with two kids.",
        "Maria, household of 3 at 1420 Shotwell St."
    );

    assert not audit.safe;
    assert len(audit.leaks) == 2;
    assert "Maria" not in audit.repaired_summary;
    assert "Shotwell" not in audit.repaired_summary;
    assert ROLE_CALLS.get("audit_anonymization", 0) == 1;
    _reset_engine();
}


test "judge_match clamps the model's unit allocation to what is left" {
    _reset_engine();
    # The model is asked for 8 units when only 3 remain. Trusting it would
    # over-allocate a pledge and promise food that does not exist.
    _use_mock([
        MatchVerdict(fits=True, score=88, units=8, rationale="ready-to-eat suits a household with no stove")
    ]);

    verdict = judge_match_safe(
        "Household of 3; no way to cook.", "food", 3,
        "food", "ready-to-eat meal boxes", "can be delivered", 3
    );

    assert verdict.fits;
    assert verdict.units == 3;
    assert ROLE_CALLS.get("judge_match", 0) == 1;
    _reset_engine();
}


test "escalation_strategy can open a second front in another category" {
    _reset_engine();
    _use_mock([
        EscalationPlan(
            widen_radius=True,
            reword_as="Household of 4 needs a room tonight; eviction already filed.",
            also_try_category="legal",
            reasoning="Stopping the eviction relieves the housing need at its source."
        )
    ]);

    plan = escalation_strategy_safe(
        "Household of 4 needs shelter.", "shelter", "high", 48, 1, "ECS Navigation Center"
    );

    assert plan.widen_radius;
    assert plan.also_try_category == "legal";
    assert plan.reword_as != "";
    _reset_engine();
}


# ===========================================================================
# Engine honesty
# ===========================================================================

test "with no key the engine reports unconfigured and says so out loud" {
    _reset_engine();
    if has_key() {
        # A key is exported in this shell, so this assertion does not apply.
        _reset_engine();
    } else {
        mode = ensure_engine();
        assert mode == "unconfigured";
        assert "no model API key" in ENGINE.reason;
        # The degradation was announced, not swallowed.
        assert len(DEGRADE_LOG) >= 1;
    }
    _reset_engine();
}


test "a fallback is always recorded, never silent" {
    _reset_engine();
    ENGINE.checked = True;
    ENGINE.mode = "unconfigured";
    ENGINE.reason = "no key";

    read = read_situation_safe("I need food, two kids, no car, no stove, 94110");

    assert read.categories[0] == "food";
    assert ENGINE.fallbacks == 1;
    assert any(["deterministic fallback" in line for line in DEGRADE_LOG]);
    assert ROLE_CALLS.get("read_situation", 0) == 0;
    _reset_engine();
}


test "drain_degrade_log hands over the lines and empties itself" {
    _reset_engine();
    _push_degrade("test", "something went wrong");
    lines = drain_degrade_log();
    assert len(lines) == 1;
    assert len(DEGRADE_LOG) == 0;
    _reset_engine();
}


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
