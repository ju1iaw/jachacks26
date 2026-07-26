"""Prove that byLLM is really doing the reasoning -- or fail loudly.

    export OPENAI_API_KEY=sk-...
    jac run scripts/verify_llm.jac

Exercises every `by llm()` role in Bridge exactly once against the real model,
then prints the per-role call tally. There is no fallback path in this app: if
the engine is not configured, or any role's call fails, this script raises and
stops right there with the real provider error -- "the API key works" is a
checked fact, not an assumption.
"""

import sys;
import from core.commons { engine_report, ensure_commons, role_tally }
import from core.reason {
    audit_anonymization_safe, escalation_strategy_safe, judge_match_safe,
    judge_requirement_safe, next_step_nudge_safe, read_situation_safe
}
import from core.agent { drain_tool_trace, plan_strategy_safe }


glob SITUATION: str = "I need food for me and my two kids this week. I lost my ID when we left the apartment, I don't have a car, and where we're staying has no stove. We also got an eviction notice for the room we're in. Zip is 94110.";

glob EXPECTED_ROLES: list[str] = [
    "read_situation",
    "audit_anonymization",
    "judge_requirement",
    "judge_match",
    "escalation_strategy",
    "next_step_nudge",
    "plan_strategy"
];


def head(title: str) {
    print("");
    print("--- " + title + " " + "-" * max(0, 60 - len(title)));
}


with entry:__main__ {
    ensure_commons();

    rep = engine_report();
    print(f"engine mode : {rep.mode}");
    print(f"model       : {rep.model}");
    if rep.reason {
        print(f"reason      : {rep.reason}");
    }
    if rep.mode != "llm" {
        print("");
        print("FAIL: byLLM is not live, so nothing below would exercise the model.");
        print("      export OPENAI_API_KEY (or ANTHROPIC_API_KEY / GOOGLE_API_KEY) and retry.");
        sys.exit(1);
    }

    head("1. read_situation");
    read = read_situation_safe(SITUATION);
    print(f"categories : {read.categories}");
    print(f"urgency    : {read.urgency}");
    print(f"household  : {read.household}");
    print(f"assets     : {read.assets}");
    print(f"anonymized : {read.anonymized_summary}");
    print(f"headline   : {read.headline}");

    head("2. audit_anonymization  (adversarial second pass)");
    audit = audit_anonymization_safe(
        "My name is Maria Alvarez, I live at 1420 Shotwell St, my number is 415-555-0199, zip 94110, two kids.",
        "Maria Alvarez at 1420 Shotwell St, household of 3, reachable on 415-555-0199."
    );
    print(f"safe       : {audit.safe}");
    print(f"leaks      : {audit.leaks}");
    print(f"repaired   : {audit.repaired_summary}");

    head("3. judge_requirement");
    verdict = judge_requirement_safe(
        SITUATION,
        ", ".join(read.assets) if read.assets else "nothing confirmed",
        "Government-issued photo ID",
        "document",
        "Get a free California ID at the DMV on Fell St -- fee waived with a shelter letter."
    );
    print(f"satisfied  : {verdict.satisfied}");
    print(f"reasoning  : {verdict.reasoning}");
    print(f"unblock    : {verdict.unblock_action}");

    head("4. judge_match  (usability, not category)");
    bad = judge_match_safe(
        "Household of 3; no way to cook, no transport.", "food", 3,
        "food", "40lb of dry rice, beans and pasta", "Bulk staples, pickup only.", 8
    );
    good = judge_match_safe(
        "Household of 3; no way to cook, no transport.", "food", 3,
        "food", "12 ready-to-eat family meal boxes, no cooking needed", "Can be delivered.", 12
    );
    print(f"dry staples  -> fits={bad.fits} score={bad.score} :: {bad.rationale}");
    print(f"ready-to-eat -> fits={good.fits} score={good.score} units={good.units} :: {good.rationale}");
    if bad.fits and not good.fits {
        print("WARNING: the model preferred food this household cannot cook.");
    }

    head("5. escalation_strategy");
    plan = escalation_strategy_safe(
        "Household of 4 needs a place to stay; eviction already filed.",
        "shelter", "high", 48, 1, "ECS Navigation Center, Hamilton Families Shelter Access"
    );
    print(f"widen      : {plan.widen_radius}");
    print(f"reword     : {plan.reword_as}");
    print(f"2nd front  : {plan.also_try_category}");
    print(f"reasoning  : {plan.reasoning}");

    head("6. next_step_nudge");
    print(next_step_nudge_safe("groceries", "Eviction Defense Collaborative"));

    head("7. plan_strategy  (ReAct agent with graph tools)");
    _ = drain_tool_trace();
    brief = plan_strategy_safe(
        SITUATION,
        ", ".join(read.categories),
        ", ".join(read.assets) if read.assets else "nothing confirmed",
        read.household,
        read.zip_prefix,
        "nothing asked yet"
    );
    path = drain_tool_trace();
    print(f"headline     : {brief.headline}");
    print(f"first action : {brief.first_action}");
    print("ordered plan :");
    for (i, action) in enumerate(brief.ordered_actions) {
        print(f"   {i + 1}. {action}");
    }
    print(f"community?   : {brief.rely_on_community}");
    print(f"risk         : {brief.risk}");
    print(f"note         : {brief.research_note}");
    print(f"open question : {brief.open_question if brief.open_question else '(none -- nothing it looked up hinged on an unknown)'}");
    print(f"  justified by: {brief.question_why if brief.question_why else '-'}");
    print("tool calls the agent CHOSE to make:");
    if path {
        for call in path {
            print(f"   - {call}");
        }
    } else {
        print("   (none -- the agent answered without consulting the graph)");
    }

    head("Result");
    final = engine_report();
    print(f"total model calls : {final.calls}");
    print(f"failures          : {final.failures}");
    print("per-role tally:");
    for line in role_tally() {
        print(f"   {line}");
    }

    # `role_tally()` renders as "role xN" -- parse it back to check every role
    # actually fired at least once.
    tally: dict[str, int] = {};
    for line in role_tally() {
        parts = line.split(" x");
        tally[parts[0]] = int(parts[1]) if len(parts) > 1 else 0;
    }
    missing = [role for role in EXPECTED_ROLES if tally.get(role, 0) < 1];

    print("");
    if missing {
        print(f"FAIL: these roles never reached the model: {', '.join(missing)}");
        sys.exit(1);
    }
    if not path {
        print("FAIL: the ReAct agent made no tool calls, so it did not research the graph.");
        sys.exit(1);
    }
    print(f"PASS: all {len(EXPECTED_ROLES)} byLLM roles answered from {final.model}, "
          f"{final.calls} calls, agent made {len(path)} graph lookups.");
}
