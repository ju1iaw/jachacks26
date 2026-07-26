"""Tests for the reasoning layer.

    jac test core/reason.test.jac

There is no fallback path in this app -- every judgement comes from `by llm()`
or the call raises. These tests cover:

  * **`by llm()` path** -- swap the module's `llm` glob for a `MockLLM` and run
    the real `by llm()`-bodied functions, proving the structured-output
    contract (schema injection, typed parse, unit clamping) without a network
    call.
  * **Engine honesty** -- with no key, `require_engine` raises immediately,
    before any of the seven roles even attempt a call. A transient per-call
    failure records itself for display but does NOT permanently downgrade the
    engine -- a rate-limit blip should not brick the app until restart.
  * **Parallel launches** -- `flow` inside a comprehension captures the loop
    variable by reference, so a future built inline reads whatever the last
    iteration left behind. That produced a real bug: every eligibility gate on
    an org got the LAST gate's verdict, silently turning blocked orgs into "you
    qualify". The `launch_*` wrappers exist to prevent it.
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
    # MockLLM stands in for a Model at runtime but is not a declared subclass, so
    # the cast is what lets it bind to the `Model`-typed glob.
    llm = MockLLM(model_name="mockllm", config={"outputs": outputs}) as Model;
    ENGINE.checked = True;
    ENGINE.mode = "llm";
    ENGINE.reason = "";
}


def _reset_engine {
    ENGINE.checked = False;
    ENGINE.mode = "unknown";
    ENGINE.calls = 0;
    ENGINE.failures = 0;
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
    # The LLM path really ran: the call was counted, no exception raised.
    assert ROLE_CALLS.get("read_situation", 0) == 1;
    assert ENGINE.failures == 0;
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


test "audit drops a 'leak' it left in the published summary" {
    _reset_engine();
    # The real failure, verbatim from a live run: the auditor reports "Household
    # of 3" as caught, and keeps it -- because repaired_summary is told to retain
    # household size. Reporting it would tell the person a fragment was removed
    # while volunteers can still read it.
    _use_mock([
        LeakAudit(
            safe=False,
            leaks=["Household of 3", "lost ID"],
            repaired_summary="Household of 3; no car, no stove access."
        )
    ]);

    audit = audit_anonymization_safe(
        "Maria here, me and my 2 kids, lost ID when we left the apartment.",
        "Household of 3; no car, no stove access, lost ID."
    );

    # "lost ID" really is gone from the published text; "Household of 3" is not.
    assert audit.leaks == ["lost ID"];
    assert "Household of 3" in audit.repaired_summary;
    _reset_engine();
}


test "a leak the auditor genuinely removed is still reported" {
    _reset_engine();
    _use_mock([
        LeakAudit(
            safe=False,
            leaks=["Maria", "Shotwell St"],
            repaired_summary="Household of 3; no car, no stove access."
        )
    ]);

    audit = audit_anonymization_safe(
        "Maria on Shotwell St with 2 kids.",
        "Maria on Shotwell St; household of 3."
    );

    assert audit.leaks == ["Maria", "Shotwell St"];
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
# Engine honesty -- no fallback, ever
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
        assert len(DEGRADE_LOG) >= 1;
    }
    _reset_engine();
}


test "require_engine raises immediately when the engine is not live, before any call" {
    _reset_engine();
    ENGINE.checked = True;
    ENGINE.mode = "unconfigured";
    ENGINE.reason = "no key";

    threw = False;
    try {
        read_situation_safe("I need food, two kids, no car, no stove, 94110");
    } except Exception as e {
        threw = True;
        assert ENGINE_UNAVAILABLE_TAG in str(e);
    }
    assert threw;
    # No fallback ran, and no call was ever attempted or counted.
    assert ROLE_CALLS.get("read_situation", 0) == 0;
    _reset_engine();
}


test "a call failure is recorded distinctly from an unconfigured engine" {
    _reset_engine();
    _note_failure("read_situation", "RateLimitError: 429 too many requests");

    # A transient call failure is a real provider error, not the "no key
    # configured" case -- the tag must NOT appear, so client code can tell them
    # apart without parsing prose.
    assert ENGINE_UNAVAILABLE_TAG not in ENGINE.reason;
    assert ENGINE.failures == 1;
    assert any(["429" in line for line in DEGRADE_LOG]);
    _reset_engine();
}


test "one failed call does not permanently downgrade the engine" {
    _reset_engine();
    ENGINE.checked = True;
    ENGINE.mode = "llm";
    ENGINE.reason = "";

    # Simulate a transient failure being recorded, the way _note_failure does.
    _note_failure("judge_requirement", "RateLimitError: 429 too many requests");

    # The engine must still be reported as live -- a single bad call is not the
    # same fact as "there is no working model connection".
    assert live();
    assert engine() == "llm";
    assert ENGINE.failures == 1;
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


# ===========================================================================
# The launch_* wrappers
# ===========================================================================
#
# `flow` inside a comprehension captures the loop variable by REFERENCE, so a
# future built inline reads whatever the last iteration left behind. That produced
# a real bug once: every eligibility gate on an org got the LAST gate's verdict,
# silently turning blocked orgs into "you qualify". Going through a function call
# gives each future its own parameter binding, which is the only reason
# `launch_requirement` / `launch_match` exist.
#
# This is tested on a pure function rather than through the real roles on purpose.
# MockLLM hands out its canned outputs in call order, and three *concurrent* calls
# have no deterministic order -- so driving this through `by llm()` would test the
# mock's scheduling, not the argument binding. Here the assertion is exact.

def _echo(tag: str) -> str {
    return tag;
}


def _launch_echo(tag: str) -> any {
    return flow _echo(tag);
}


test "a flow launched through a wrapper binds its own argument" {
    tags = ["first", "second", "third", "fourth", "fifth"];
    pending = [_launch_echo(t) for t in tags];
    got: list[str] = [wait f for f in pending];

    # Inline `flow _echo(t)` here would yield five copies of "fifth".
    assert got == tags;
}


test "the real launchers hand back one future per call" {
    gates = [
        ["Government-issued photo ID", "document", "Visit the DMV."],
        ["Household income under 125% FPL", "income", ""]
    ];
    pending = [
        launch_requirement("I lost my ID.", "nothing confirmed", g[0], g[1], g[2])
        for g in gates
    ];
    assert len(pending) == 2;
    assert pending[0] is not pending[1];
}
