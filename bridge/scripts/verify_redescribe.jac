"""Prove that re-describing a situation cleans up after itself.

    rm -rf .jac && jac run scripts/verify_redescribe.jac

Needs a real key -- there is no fallback path, so this exercises the same model
calls the app makes. It **exits non-zero** if any invariant below is violated.

`jac run` echoes every spawned walker's reports, so most of the output is board
dumps. For just the verdict:

    rm -rf .jac && jac run scripts/verify_redescribe.jac | grep -E '^(===|  )'

Re-intake is destructive by design: it retires the old needs so the commons never
carries two live asks for the same household. Three things have to be true after
it runs, and none of them are visible from a single request:

  1. the retired needs are gone from the commons, so no volunteer is left working
     an ask that no longer exists;
  2. any units a retired need had taken off a donor's pledge are **given back**,
     because the `Matched` edge that recorded them is deleted along with the need
     -- miss this and the shelf drains a little on every re-describe until the
     matcher reports that nothing fits against pledges nobody ever used;
  3. the answered-question trail is cleared, because restating your situation is
     how you correct an answer you gave earlier -- while `AnswerWalker`'s own
     re-plan keeps it, since the story it submits already contains the answer.
"""

import sys;
import from core.commons { choose_role, ensure_commons, engine_report }
import from core.walkers { AnswerWalker, CommunityBoard, IntakeWalker }


glob FAILURES: list[str] = [];


def line(title: str) {
    print("");
    print("=== " + title + " " + "=" * max(0, 62 - len(title)));
}


def check(label: str, ok: bool, detail: str) {
    print(f"  [{'PASS' if ok else 'FAIL'}] {label}");
    if detail {
        print(f"         {detail}");
    }
    if not ok {
        FAILURES.append(label);
    }
}


"""Every pledge on the shelf, as `description -> (remaining, capacity)`."""
def shelf -> dict[str, tuple] {
    view = (root spawn CommunityBoard()).reports[0];
    out: dict[str, tuple] = {};
    for p in view.pledges {
        out[p.description] = (p.remaining, p.capacity);
    }
    return out;
}


def need_codes -> list[str] {
    view = (root spawn CommunityBoard()).reports[0];
    return [n.code for n in view.needs];
}


def show_shelf(state: dict[str, tuple]) {
    for (desc, pair) in state.items() {
        print(f"    {pair[0]:>3}/{pair[1]:<3} left  {desc}");
    }
}


with entry:__main__ {
    ensure_commons();
    choose_role("seeker", "Maria");

    rep = engine_report();
    if rep.mode != "llm" {
        print("!! No working model connection -- there is no fallback, so nothing here can run.");
        print("!! export OPENAI_API_KEY (or ANTHROPIC_API_KEY / GOOGLE_API_KEY) and retry.");
        sys.exit(1);
    }
    print(f"engine: {rep.mode} / {rep.model}");

    # -------------------------------------------------------------------
    line("1. First description");
    # -------------------------------------------------------------------
    first = root spawn IntakeWalker(
        situation="I need food for me and my two kids this week. I lost my ID when we left the apartment, I don't have a car, and where we're staying has no stove. We also got an eviction notice for the room we're in. Zip is 94110."
    );
    board = first.reports[0];
    opening_codes = [n.code for n in board.needs];
    print(f"  needs opened: {opening_codes}");

    # The seed pledges auto-match on broadcast, so the shelf is already down.
    after_first = shelf();
    print("  shelf after intake (the matcher already ran on its own):");
    show_shelf(after_first);

    consumed = {
        d: pair for (d, pair) in after_first.items() if pair[0] < pair[1]
    };
    check(
        "a seeded pledge was actually consumed by the match",
        len(consumed) > 0,
        f"{len(consumed)} pledge(s) drawn down -- without this the rest proves nothing"
    );

    # -------------------------------------------------------------------
    line("2. AnswerWalker re-plans and KEEPS the trail");
    # -------------------------------------------------------------------
    question = "";
    for brief in board.strategy {
        if brief.open_question {
            question = brief.open_question;
        }
    }
    if question {
        print(f"  agent asked: {question}");
        replan = root spawn AnswerWalker(
            answer="No -- I lost everything when we left, so I don't have that.",
            question=question
        );
        answered_board = replan.reports[0];
        check(
            "the answered trail survives an answer-driven re-plan",
            len(answered_board.answered) > 0,
            f"trail: {answered_board.answered}"
        );
    } else {
        print("  (the agent had no open question this run -- skipping)");
    }

    before_redescribe = shelf();
    codes_before = need_codes();
    print(f"  needs on the commons before re-describing: {codes_before}");

    # -------------------------------------------------------------------
    line("3. Re-describing by hand");
    # -------------------------------------------------------------------
    # Exactly what the "Something's changed - redo this" button spawns: a bare
    # IntakeWalker, no keep_answers, on a story the person retyped.
    second = root spawn IntakeWalker(
        situation="Things have changed. My sister can take the kids for a couple of weeks, so it is just me now. I found my birth certificate but still have no photo ID, and I still need somewhere to sleep. The eviction hearing is next Tuesday. Zip is 94110."
    );
    redone = second.reports[0];
    codes_after = need_codes();
    after_second = shelf();

    print(f"  needs after re-describing: {codes_after}");
    print("  shelf after re-describing:");
    show_shelf(after_second);

    # -------------------------------------------------------------------
    line("Invariants");
    # -------------------------------------------------------------------
    leftover = [c for c in codes_before if c in codes_after];
    check(
        "every need from the old description is off the commons",
        len(leftover) == 0,
        f"still live: {leftover}" if leftover else "no stale asks left for a volunteer to work"
    );

    restored = True;
    detail: list[str] = [];
    for (desc, pair) in before_redescribe.items() {
        was = pair[0];
        now = after_second.get(desc, (was, pair[1]))[0];
        if now < was {
            restored = False;
            detail.append(f"{desc}: {was} -> {now}");
        }
    }
    check(
        "no pledge came out of the re-describe with fewer units than it went in",
        restored,
        "; ".join(detail) if detail else "the shelf was credited back as needs were retired"
    );

    check(
        "the answered trail is cleared by a hand-written re-describe",
        len(redone.answered) == 0,
        f"still carried: {redone.answered}" if redone.answered
        else "the person can now correct an answer by restating their situation"
    );

    # -------------------------------------------------------------------
    line("Result");
    # -------------------------------------------------------------------
    if FAILURES {
        print(f"  {len(FAILURES)} invariant(s) violated:");
        for f in FAILURES {
            print(f"    - {f}");
        }
        sys.exit(1);
    }
    print("  all invariants hold -- re-describing cleans up after itself.");
}
