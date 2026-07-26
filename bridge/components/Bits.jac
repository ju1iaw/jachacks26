"""Small presentational pieces shared by both sides of Bridge."""

import from ..core.graph { PlanStep, NeedCard, StrategyView, WalkerTrace }


glob STATUS_PILL: dict[str, str] = {
    "open": "cool",
    "blocked": "danger",
    "covered": "ok",
    "optional": "",
    "matched": "cool",
    "fulfilled": "ok"
};

glob STEP_WORD: dict[str, str] = {
    "open": "you qualify",
    "blocked": "blocked",
    "covered": "covered",
    "optional": "no longer urgent"
};

glob NEED_WORD: dict[str, str] = {
    "open": "waiting",
    "matched": "help on the way",
    "fulfilled": "covered"
};

glob URGENCY_PILL: dict[str, str] = {
    "critical": "danger",
    "high": "warm",
    "medium": "",
    "low": ""
};


def:pub Brand(tagline: str = "") -> JsxElement {
    return <div className="brand">
        <div className="brand-mark"></div>
        <span>Bridge</span>
        {if tagline {
            <small key="t">{" - " + tagline}</small>
        }}
    </div>;
}


def:pub Pill(text: str, tone: str = "") -> JsxElement {
    return <span className={"pill " + tone}>{text}</span>;
}


def:pub Stat(n: int, k: str) -> JsxElement {
    return <div className="stat">
        <div className="n">{str(n)}</div>
        <div className="k">{k}</div>
    </div>;
}


def:pub StepRow(step: PlanStep, idx: int) -> JsxElement {
    tone = STATUS_PILL.get(step.status, "");
    word = STEP_WORD.get(step.status, step.status);
    if step.unblocks and step.status == "open" {
        word = "do this first";
        tone = "warm";
    }
    return <div className={"step " + step.status}>
        <div className="idx">{str(idx).rjust(2, "0")}</div>
        <div>
            <div className="row" style={{"justifyContent": "space-between", "alignItems": "flex-start"}}>
                <h4>{step.title}</h4>
                <Pill text={word} tone={tone}/>
            </div>
            <p className="detail">{step.detail}</p>
            {if step.blocker {
                <div className="why" key="b">
                    <b>{"Gate: "}</b>{step.blocker}
                </div>
            }}
            {if step.reasoning {
                <div className="why" key="r">
                    <b>{"Why: "}</b>{step.reasoning}
                </div>
            }}
            {if step.org_phone {
                <p className="small muted" key="p" style={{"marginTop": "8px"}}>
                    {step.org_address + "  ·  " + step.org_phone}
                </p>
            }}
        </div>
    </div>;
}


def:pub NeedTile(card: NeedCard, action: any = None) -> JsxElement {
    return <div className={"tile " + card.status}>
        <div className="row" style={{"justifyContent": "space-between"}}>
            <span className="code">{card.code}</span>
            <div className="row" style={{"gap": "6px"}}>
                <Pill text={card.urgency} tone={URGENCY_PILL.get(card.urgency, "")}/>
                <Pill text={NEED_WORD.get(card.status, card.status)} tone={STATUS_PILL.get(card.status, "")}/>
            </div>
        </div>
        <p className="summary">{card.summary}</p>
        <p className="small muted">
            {"ZIP " + card.zip_prefix + "xx  ·  household of " + str(card.household) + "  ·  via " + card.via_org + "  ·  " + card.age_label}
        </p>
        {if card.escalations > 0 {
            <p className="small" key="e" style={{"color": "var(--warm)"}}>
                {"Escalated " + str(card.escalations) + "x - broadcast radius now tier " + str(card.broadcast_tier)}
            </p>
        }}
        {if card.matched_with {
            <div className="why" key="m">
                <b>{"Matched: "}</b>{card.matched_with}
                <div style={{"marginTop": "5px"}}>{card.match_rationale}</div>
            </div>
        }}
        {if action is not None {
            <div key="a">{action}</div>
        }}
    </div>;
}


"""What is actually answering questions, stated plainly.

Deliberately not a decorative "AI powered" chip: when the model is not reachable
this turns red and says so, and the live call count is the evidence that byLLM
really is doing the reasoning. There is no fallback in this app -- when this
badge is not green, every model-backed action will error until it is fixed.
"""
def:pub EngineBadge(
    mode: str,
    model: str,
    calls: int,
    reason: str,
    roles: list[str]
) -> JsxElement {
    online = mode == "llm";
    label = ("byLLM live - " + model) if online else "NO MODEL CONNECTION";
    return <div className={"pill " + ("ok" if online else "danger")} title={", ".join(roles) if roles else "no model calls yet"}>
        <span className="dot"></span>
        <span>{label}</span>
        {if online {
            <span key="c" style={{"opacity": "0.75"}}>{"  " + str(calls) + " model calls"}</span>
        }}
        {if not online {
            <span key="f" style={{"opacity": "0.75"}}>
                {("  -  " + reason) if reason else "  -  set an API key and restart"}
            </span>
        }}
    </div>;
}


"""The ReAct caseworker's brief, with the research it chose to do.

`research_path` is the part worth showing: those lines are the tool calls the
agent decided to make against the live graph before it committed to an order.
"""
def:pub StrategyCard(brief: StrategyView) -> JsxElement {
    return <div className="card">
        <div className="row" style={{"justifyContent": "space-between", "alignItems": "flex-start"}}>
            <div className="eyebrow">Caseworker agent</div>
            {if brief.rely_on_community {
                <Pill key="c" text="community can cover this" tone="ok"/>
            }}
        </div>
        <h3 style={{"fontSize": "18px", "margin": "8px 0 10px"}}>{brief.headline}</h3>

        <div className="why">
            <b>{"Do this first: "}</b>{brief.first_action}
        </div>

        <div className="eyebrow" style={{"margin": "16px 0 8px"}}>In this order</div>
        <ol style={{"margin": "0 0 0 18px", "padding": "0"}}>
            {for (i, action) in enumerate(brief.ordered_actions) {
                <li key={str(i)} className="small" style={{"marginBottom": "6px"}}>{action}</li>
            }}
        </ol>

        {if brief.risk {
            <p className="small muted" key="r" style={{"marginTop": "12px"}}>
                <b>{"Most likely to go wrong: "}</b>{brief.risk}
            </p>
        }}

        <div className="eyebrow" style={{"margin": "16px 0 8px"}}>
            Research the agent chose to run
            <span className="hint">every line is a real read against the live graph</span>
        </div>
        {if len(brief.research_path) == 0 {
            <p className="small muted" key="none">
                The agent answered without looking anything up this time.
            </p>
        }}
        <div className="feed">
            {for (i, call) in enumerate(brief.research_path) {
                <div className="feed-item" key={str(i)}>
                    <div className="feed-rail"><span></span></div>
                    <div className="feed-d" style={{"fontFamily": "ui-monospace, monospace"}}>{call}</div>
                </div>
            }}
        </div>

        {if brief.research_note {
            <p className="small muted" key="n" style={{"marginTop": "10px"}}>{brief.research_note}</p>
        }}
    </div>;
}


"""The one question the caseworker agent could not answer from what it was told.

`why` is the load-bearing part: it names the organisation and requirement that
hinge on the answer and says what changes either way, so this reads as a decision
worth 5 seconds rather than a form field. Answering re-runs the whole pipeline.
"""
def:pub OpenQuestion(
    question: str,
    why: str,
    answer: str,
    busy: bool,
    on_answer: Callable[[str], None],
    on_change: Callable[[str], None]
) -> JsxElement {
    return <div className="card" style={{"borderColor": "var(--cool)"}}>
        <div className="eyebrow">One thing would change your plan</div>
        <p style={{"fontSize": "16px", "margin": "10px 0 8px", "fontWeight": "600"}}>{question}</p>
        {if why {
            <div className="why" key="w">{why}</div>
        }}
        <div className="row" style={{"marginTop": "14px", "gap": "8px"}}>
            <button
                className="btn primary sm"
                onClick={lambda { on_answer("yes"); }}
                disabled={busy}
            >Yes</button>
            <button
                className="btn sm"
                onClick={lambda { on_answer("no"); }}
                disabled={busy}
            >No</button>
            <span className="small muted">or say more:</span>
        </div>
        <div className="row" style={{"marginTop": "8px", "gap": "8px"}}>
            <input
                className="field"
                value={answer}
                placeholder="I have a shelter letter but no ID"
                disabled={busy}
                onChange={lambda (e: ChangeEvent) { on_change(e.target.value); }}
            />
            <button
                className="btn cool sm"
                onClick={lambda { on_answer(answer); }}
                disabled={busy or not answer}
            >{"Re-planning..." if busy else "Send"}</button>
        </div>
        <p className="small muted" style={{"marginTop": "10px"}}>
            Answering re-checks every requirement and re-orders your plan - it does
            not just record the answer.
        </p>
    </div>;
}


def:pub AnsweredTrail(rows: list[str]) -> JsxElement {
    return <div className="card">
        <div className="eyebrow" style={{"marginBottom": "10px"}}>What you have told us</div>
        <div className="feed">
            {for (i, row) in enumerate(rows) {
                <div className="feed-item" key={str(i)}>
                    <div className="feed-rail"><span></span></div>
                    <div className="feed-d">{row}</div>
                </div>
            }}
        </div>
    </div>;
}


"""What the auditor stripped before anything was published.

The claim "no identity crosses the boundary" is worth very little as a sentence
in a README; this shows the specific fragments a second model pass caught and
removed from the text volunteers actually see.
"""
def:pub PrivacyNote(leaks: list[str]) -> JsxElement {
    clean = len(leaks) == 0;
    return <div className="card" style={{"borderColor": "var(--ok)" if clean else "var(--warm)"}}>
        <div className="row" style={{"justifyContent": "space-between"}}>
            <div className="eyebrow">Privacy auditor</div>
            <Pill text={"clean" if clean else str(len(leaks)) + " leak(s) stripped"} tone={"ok" if clean else "warm"}/>
        </div>
        {if clean {
            <p className="small muted" key="c" style={{"marginTop": "8px"}}>
                A second model pass audited your public summary and found nothing
                that could identify you.
            </p>
        }}
        {if not clean {
            <div key="l" style={{"marginTop": "8px"}}>
                <p className="small muted" style={{"marginBottom": "8px"}}>
                    Caught and removed before any volunteer could see it:
                </p>
                {for (i, leak) in enumerate(leaks) {
                    <div className="why" key={str(i)} style={{"marginBottom": "6px"}}>{leak}</div>
                }}
            </div>
        }}
    </div>;
}


def:pub ActivityFeed(items: list[WalkerTrace]) -> JsxElement {
    return <div className="card">
        <div className="eyebrow" style={{"marginBottom": "10px"}}>Walker activity</div>
        <p className="small muted" style={{"marginBottom": "12px"}}>
            Every line was written by a different walker, in a different request.
            They never call each other - they only touch the same graph.
        </p>
        <div className="feed">
            {if len(items) == 0 {
                <p className="small muted" key="none">Nothing has run yet.</p>
                skip;
            }}
            {for (i, a) in enumerate(items) {
                <div className="feed-item" key={str(i)}>
                    <div className="feed-rail"><span></span></div>
                    <div>
                        <div className="feed-w">{a.walker}</div>
                        <div className="feed-d">{a.detail}</div>
                    </div>
                </div>
            }}
        </div>
    </div>;
}
