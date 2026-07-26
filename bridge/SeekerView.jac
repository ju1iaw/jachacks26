"""Bridge - the view for someone in an acute situation.

One textarea in, a live plan out. The plan is not fetched once and frozen: this
component polls `FulfillmentWalker`, which re-reads the graph every time. When a
volunteer's `MatchWalker` attaches a `Matched` edge in a completely separate
session, this view picks it up on the next tick with no push, no socket and no
coordination between the two walkers.
"""

import from react { useEffect }
import from .components.Bits { ActivityFeed, NeedTile, Pill, Stat, StepRow }

sv import from .core.graph { NeedCard, PlanStep, SeekerBoard, WalkerTrace }
sv import from .core.walkers { FulfillmentWalker, IntakeWalker }


glob EXAMPLE: str = "I need food for me and my two kids this week. I lost my ID when we left the apartment, I don't have a car, and where we're staying has no stove. Zip is 94110.";


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

    async def refresh -> None;
    async def submit -> None;
    def use_example(e: MouseEvent) -> None;

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
        {if not has_plan {
            <div className="card" key="intake" style={{"maxWidth": "720px", "margin": "0 auto"}}>
                <div className="eyebrow">Tell us once</div>
                <h1 style={{"fontSize": "24px", "margin": "8px 0 6px"}}>
                    {"What's going on, " + display_name + "?"}
                </h1>
                <p className="muted small" style={{"marginBottom": "16px"}}>
                    Plain words are fine. Bridge checks what each place near you actually
                    requires at the door, and tells you the ones that would turn you away
                    before you make the trip.
                </p>
                <textarea
                    className="field"
                    value={situation}
                    placeholder="I need food for me and my two kids this week..."
                    onChange={lambda (e: ChangeEvent) { situation = e.target.value; }}
                />
                <div className="row" style={{"marginTop": "12px"}}>
                    <button className="btn primary" onClick={submit} disabled={busy}>
                        {"Building your plan..." if busy else "Build my plan"}
                    </button>
                    <button className="btn ghost sm" onClick={use_example}>Use the demo situation</button>
                    <div className="spacer" style={{"flex": "1"}}></div>
                    <Pill text={"reasoning: " + engine} tone=""/>
                </div>
                {if error {
                    <p className="err" key="e" style={{"marginTop": "10px"}}>{error}</p>
                }}
            </div>
            skip;
        }}

        {if has_plan {
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
                    <div className="eyebrow">Your situation</div>
                    <h1 style={{"fontSize": "22px", "margin": "8px 0 10px"}}>{headline}</h1>
                    <div className="stats">
                        <Stat n={actionable} k="ready now"/>
                        <Stat n={blocked} k="blocked"/>
                        <Stat n={covered} k="covered by a donor"/>
                    </div>
                </div>

                <div className="cols" style={{"marginTop": "22px"}}>
                    <div>
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
                    <ActivityFeed items={activity}/>
                </div>
            </div>
        }}
    </div>;
}
