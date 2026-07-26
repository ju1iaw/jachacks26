"""Prove that byLLM is really doing the reasoning -- or fail loudly.

    export OPENAI_API_KEY=sk-...
    jac run scripts/verify_llm.jac

Exercises every `by llm()` role in Bridge exactly once against the real model,
then prints the per-role call tally. If any role answered from a deterministic
fallback, this exits with a non-zero status and names the role, so "the API key
works" is a checked fact rather than an assumption.

Run it with `BRIDGE_STRICT_LLM=1` to make the fallbacks raise at the point of use
instead of substituting -- that is the mode in which no answer can possibly be
heuristic.
"""

import sys;
import from core.commons { engine_report, ensure_commons, role_tally }
import from core.reason {
    ask_clarifying_safe, audit_anonymization_safe, escalation_strategy_safe,
    judge_match_safe, judge_requirement_safe, next_step_nudge_safe,
    read_situation_safe, strict_mode
}
import from core.agent { drain_tool_trace, plan_strategy_safe }


glob SITUATION: str = "I need food for me and my two kids this week. I lost my ID when we left the apartment, I don't have a car, and where we're staying has no stove. Zip is 94110.";

glob EXPECTED_ROLES: list[str] = [
    "read_situation",
    "audit_anonymization",
    "ask_clarifying",
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
    print(f"strict mode : {strict_mode()}");
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

    head("3. ask_clarifying");
    clar = ask_clarifying_safe(SITUATION, ", ".join(read.categories), ", ".join(read.assets));
    print(f"needed     : {clar.needed}");
    print(f"question   : {clar.question}");
    print(f"why        : {clar.why}");

    head("4. judge_requirement");
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

    head("5. judge_match  (usability, not category)");
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

    head("6. escalation_strategy");
    plan = escalation_strategy_safe(
        "Household of 4 needs a place to stay; eviction already filed.",
        "shelter", "high", 48, 1, "ECS Navigation Center, Hamilton Families Shelter Access"
    );
    print(f"widen      : {plan.widen_radius}");
    print(f"reword     : {plan.reword_as}");
    print(f"2nd front  : {plan.also_try_category}");
    print(f"reasoning  : {plan.reasoning}");

    head("7. next_step_nudge");
    print(next_step_nudge_safe("groceries", "Eviction Defense Collaborative"));

    head("8. plan_strategy  (ReAct agent with graph tools)");
    _ = drain_tool_trace();
    brief = plan_strategy_safe(
        SITUATION,
        ", ".join(read.categories),
        ", ".join(read.assets) if read.assets else "nothing confirmed",
        read.household,
        read.zip_prefix
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
    print(f"fallback answers  : {final.fallbacks}");
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
    if final.fallbacks > 0 {
        print(f"FAIL: {final.fallbacks} answer(s) came from a deterministic fallback, not the model.");
        sys.exit(1);
    }
    if missing {
        print(f"FAIL: these roles never reached the model: {', '.join(missing)}");
        sys.exit(1);
    }
    if not path {
        print("FAIL: the ReAct agent made no tool calls, so it did not research the graph.");
        sys.exit(1);
    }
    print(f"PASS: all {len(EXPECTED_ROLES)} byLLM roles answered from {final.model}, "
          f"{final.calls} calls, zero fallbacks, agent made {len(path)} graph lookups.");
}
