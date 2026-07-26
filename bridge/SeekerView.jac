"""Bridge - the view for someone in an acute situation.

One textarea in, a live plan out. The plan is not fetched once and frozen: this
component polls `FulfillmentWalker`, which re-reads the graph every time. When a
`Matched` edge appears, this view picks it up on the next tick with no push, no
socket and no coordination between the walkers that wrote it and the one reading
it -- and it makes no difference which session attached it. Matching is woken by
the need landing or the pledge landing, so the edge may have been written inside
this person's own intake request or inside a stranger's, seconds later.
"""

import from react { useEffect }
import from .components.Bits {
    ActivityFeed, AnsweredTrail, EngineBadge, NeedTile, OpenQuestion, Pill,
    PrivacyNote, Stat, StepRow, StrategyCard
}

sv import from .core.graph {
    NeedCard, PlanStep, SeekerBoard, StrategyView, WalkerTrace
}
sv import from .core.walkers { AnswerWalker, FulfillmentWalker, IntakeWalker }


glob EXAMPLE: str = "I need food for me and my two kids this week. I lost my ID when we left the apartment, I don't have a car, and where we're staying has no stove. We also got an eviction notice for the room we're in. Zip is 94110.";


def:pub SeekerView(display_name: str) -> JsxElement {
    has situation: str = "";
    has steps: list[PlanStep] = [];
    has needs: list[NeedCard] = [];
    has activity: list[WalkerTrace] = [];
    has headline: str = "";
    has nudge: str = "";
    has engine: str = "";
    has has_plan: bool = False;
    has busy: bool = False;
    has error: str = "";

    # Client-only: the person asked to re-describe while a plan already exists.
    # It is deliberately NOT read off the board -- `apply` runs on every 3s poll
    # and would otherwise close the textarea under someone mid-sentence.
    has editing: bool = False;

    # The caseworker agent's brief (0 or 1), what the privacy auditor stripped,
    # and the one question the agent decided was worth asking.
    has strategy: list[StrategyView] = [];
    has answered: list[str] = [];
    has privacy_leaks: list[str] = [];

    # The answer being typed, and whether a re-plan is in flight.
    has answer_draft: str = "";
    has answering: bool = False;

    # Engine evidence, rendered as a badge. `engine_calls` is the number that
    # answers "is that really the model?" without anyone taking it on trust.
    has engine_model: str = "";
    has engine_reason: str = "";
    has engine_calls: int = 0;
    has engine_roles: list[str] = [];

    def apply(board: SeekerBoard) -> None;
    async def refresh -> None;
    async def submit -> None;
    async def send_answer(value: str) -> None;
    def set_draft(value: str) -> None;
    def use_example(e: MouseEvent) -> None;
    def start_over(e: MouseEvent) -> None;
    def keep_plan(e: MouseEvent) -> None;

    async can with entry {
        refresh();
    }

    useEffect(lambda {
        timer = setInterval(lambda { refresh(); }, 3000);
        return lambda { clearInterval(timer); };
    }, []);

    covered = len([s for s in steps if s.status == "covered"]);
    blocked = len([s for s in steps if s.status == "blocked"]);
    actionable = len([s for s in steps if s.status == "open"]);

    return <div className="wrap">
        {if editing or not has_plan {
            <div className="card" key="intake" style={{"maxWidth": "720px", "margin": "0 auto"}}>
                <div className="eyebrow">{"Tell us again" if editing else "Tell us once"}</div>
                <h1 style={{"fontSize": "24px", "margin": "8px 0 6px"}}>
                    {("What's changed, " if editing else "What's going on, ") + display_name + "?"}
                </h1>
                <p className="muted small" style={{"marginBottom": "16px"}}>
                    {"Edit this however you like. Sending it replans from scratch: the old steps go, and the asks already out on the commons for you are retired so nobody works a stale one."
                     if editing else
                     "Plain words are fine. Bridge checks what each place near you actually requires at the door, and tells you the ones that would turn you away before you make the trip."}
                </p>
                <textarea
                    className="field"
                    value={situation}
                    placeholder="I need food for me and my two kids this week..."
                    onChange={lambda (e: ChangeEvent) { situation = e.target.value; }}
                />
                <div className="row" style={{"marginTop": "12px"}}>
                    <button className="btn primary" onClick={submit} disabled={busy}>
                        {("Rebuilding your plan..." if busy else "Rebuild my plan")
                         if editing else
                         ("Building your plan..." if busy else "Build my plan")}
                    </button>
                    <button className="btn ghost sm" onClick={use_example}>Use the demo situation</button>
                    {if editing {
                        <button className="btn ghost sm" key="keep" onClick={keep_plan} disabled={busy}>
                            Keep the plan I have
                        </button>
                    }}
                    <div className="spacer" style={{"flex": "1"}}></div>
                    <EngineBadge
                        mode={engine}
                        model={engine_model}
                        calls={engine_calls}
                        reason={engine_reason}
                        roles={engine_roles}
                    />
                </div>
                {if error {
                    <p className="err" key="e" style={{"marginTop": "10px"}}>{error}</p>
                }}
            </div>
            skip;
        }}

        {if has_plan and not editing {
            <div key="plan">
                {if nudge {
                    <div className="card" key="n" style={{
                        "borderColor": "var(--ok)",
                        "background": "#141a16",
                        "marginBottom": "18px"
                    }}>
                        <div className="row">
                            <span className="pill ok"><span className="dot"></span>update</span>
                            <span style={{"fontSize": "15.5px"}}>{nudge}</span>
                        </div>
                    </div>
                }}

                <div className="card">
                    <div className="row" style={{"justifyContent": "space-between", "alignItems": "flex-start"}}>
                        <div className="eyebrow">Your situation</div>
                        <div className="row" style={{"gap": "8px"}}>
                            <button className="btn ghost sm" onClick={start_over}>
                                Something's changed - redo this
                            </button>
                            <EngineBadge
                                mode={engine}
                                model={engine_model}
                                calls={engine_calls}
                                reason={engine_reason}
                                roles={engine_roles}
                            />
                        </div>
                    </div>
                    <h1 style={{"fontSize": "22px", "margin": "8px 0 10px"}}>{headline}</h1>
                    <div className="stats">
                        <Stat n={actionable} k="ready now"/>
                        <Stat n={blocked} k="blocked"/>
                        <Stat n={covered} k="covered by a donor"/>
                    </div>
                </div>

                {for (i, brief) in enumerate(strategy) {
                    <div key={"q" + str(i)} style={{"marginTop": "18px"}}>
                        {if brief.open_question {
                            <OpenQuestion
                                question={brief.open_question}
                                why={brief.question_why}
                                answer={answer_draft}
                                busy={answering}
                                on_answer={send_answer}
                                on_change={set_draft}
                            />
                        }}
                    </div>
                }}

                <div className="cols" style={{"marginTop": "22px"}}>
                    <div>
                        {for (i, brief) in enumerate(strategy) {
                            <StrategyCard key={str(i)} brief={brief}/>
                        }}

                        <div className="section-title">
                            Your plan
                            <span className="hint">
                                reasoned per place, re-ordered so blockers come first
                            </span>
                        </div>
                        <div className="stack">
                            {for (i, s) in enumerate(steps) {
                                <StepRow key={str(i)} step={s} idx={i + 1}/>
                            }}
                        </div>

                        <div className="section-title">
                            Quietly asked on your behalf
                            <span className="hint">
                                no name, no address, no contact - this is all a volunteer ever sees
                            </span>
                        </div>
                        <div className="grid">
                            {for (i, n) in enumerate(needs) {
                                <NeedTile key={str(i)} card={n}/>
                            }}
                        </div>
                    </div>
                    <div className="stack">
                        {if len(answered) > 0 {
                            <AnsweredTrail key="at" rows={answered}/>
                        }}
                        <PrivacyNote leaks={privacy_leaks}/>
                        <ActivityFeed items={activity}/>
                    </div>
                </div>
            </div>
        }}
    </div>;
}
