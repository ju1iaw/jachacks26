"""Small presentational pieces shared by both sides of Bridge."""

import from ..core.graph { PlanStep, NeedCard, WalkerTrace }


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
