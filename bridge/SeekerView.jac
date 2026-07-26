"""Bridge - seeker chat and assistance page.

Center: ask for help, get expandable program suggestions. Accept moves a card
into Ongoing; swipe left clears it into All past suggestions. Matched helper
offers that are not yet redeemed also land under Ongoing.
"""

import from react { useEffect }
import from .components.Bits {
    ActivityFeed, AnsweredTrail, EngineBadge, PrivacyNote, StrategyCard
}
import from .components.Suggestions {
    ActionStep, OngoingPanel, Suggestion, SuggestionCard, demo_suggestions
}

sv import from .core.graph {
    NeedCard, PlanStep, SeekerBoard, StrategyView, WalkerTrace
}
sv import from .core.walkers { AnswerWalker, FulfillmentWalker, IntakeWalker }


glob EXAMPLE: str = "I need food for me and my two kids this week. I lost my ID when we left the apartment, I don't have a car, and where we're staying has no stove. We also got an eviction notice for the room we're in. Zip is 94110.";


def sug_id(name: str) -> str {
    raw = name.lower().replace(" ", "-").replace(",", "").replace(".", "");
    return "org-" + raw[:48];
}


"""Render one org as a card. `qualify` are the unblock steps written for it.

`EligibilityPathWalker` emits each unblock action as its own `documents` PlanStep
ranked just above the org it unblocks, so the graph keeps them individually
addressable. This UI shows one card per org, so they are folded back in here as
action lines rather than dropped -- they carry the model's actual `unblock_action`
for this person, which is the whole point of judging the gate.
"""
def step_to_suggestion(step: PlanStep, qualify: list[PlanStep] = []) -> Suggestion {
    name = step.org_name if step.org_name else step.title;
    blocked = step.status == "blocked";
    steps: list[ActionStep] = [];

    if blocked {
        for fix in qualify {
            label = fix.title[7:] if fix.title.startswith("First: ") else fix.title;
            steps = steps + [ActionStep(text="To qualify — " + label + ": " + fix.detail)];
        }
        if len(qualify) == 0 {
            # Nothing reasoned for this gate, so fall back to naming it plainly
            # rather than inventing an unblock the model did not produce.
            if step.blocker {
                steps = steps + [ActionStep(text="To qualify, you still need: " + step.blocker)];
            }
        }
        if step.detail {
            steps = steps + [ActionStep(text=step.detail)];
        }
    } else {
        primary = step.detail if step.detail else "You look eligible — you can go ahead.";
        steps = steps + [ActionStep(text=primary)];
    }

    link = "";
    link_label = "";
    if step.org_phone {
        link = "tel:" + step.org_phone.replace(" ", "").replace("-", "");
        link_label = "Call " + step.org_phone;
        steps = steps + [ActionStep(
            text="Call if you need hours or to confirm what to bring.",
            link=link,
            link_label=link_label
        )];
    }
    if step.org_address {
        steps = steps + [ActionStep(text="Go to " + step.org_address + ".")];
    }

    desc = (
        "You don't qualify yet — follow the steps below, then you can use this program."
        if blocked
        else "You appear eligible for this program."
    );
    if step.reasoning and not blocked {
        desc = step.reasoning;
    }

    return Suggestion(
        id=sug_id(name),
        name=name,
        description=desc,
        steps=steps,
        kind="blocked" if blocked else "program",
        badge="qualify first" if blocked else "eligible"
    );
}


def board_to_suggestions(steps: list[PlanStep]) -> list[Suggestion] {
    # One card per organisation (or title). The `documents` rows are not cards of
    # their own -- they are the unblock actions for the org they name, and get
    # folded into that org's card below.
    keys: list[str] = [];
    for step in steps {
        if step.category == "documents" {
            continue;
        }
        key = step.org_name if step.org_name else step.title;
        if key not in keys {
            keys = keys + [key];
        }
    }

    out: list[Suggestion] = [];
    for key in keys {
        group = [
            s for s in steps
            if s.category != "documents" and (s.org_name if s.org_name else s.title) == key
        ];
        if len(group) == 0 {
            continue;
        }
        # Prefer a blocked row when mixed so qualify steps stay visible.
        pick = group[0];
        for s in group {
            if s.status == "blocked" {
                pick = s;
                break;
            }
        }
        qualify = [
            s for s in steps
            if s.category == "documents" and s.org_name == key
        ];
        out = out + [step_to_suggestion(pick, qualify)];
    }
    return out;
}


def need_to_suggestion(card: NeedCard) -> Suggestion {
    who = card.matched_with if card.matched_with else "a community helper";
    return Suggestion(
        id="need-" + card.code,
        name="Help from " + who,
        description=card.summary,
        steps=[
            ActionStep(
                text="A helper has offered to cover this. Confirm once you have received the help."
            ),
            ActionStep(
                text=card.match_rationale if card.match_rationale else "Unconfirmed — still waiting on pickup or delivery."
            )
        ],
        kind="helper",
        badge="helper offer"
    );
}


def:pub SeekerView(
    display_name: str,
    contact_method: str = "",
    contact_value: str = "",
    location: str = "",
    panel: str = "home",
    onHome: Callable[[], None] | None = None
) -> JsxElement {
    has situation: str = "";
    has inbox: list[Suggestion] = [];
    has ongoing: list[Suggestion] = [];
    has past: list[Suggestion] = [];
    has ongoing_open: bool = True;
    has busy: bool = False;
    has error: str = "";
    has nudge: str = "";

    # The one thing the caseworker agent's research could not settle. It rides on
    # `strategy[0]`, next to the research that justifies asking it, rather than
    # coming from a role of its own -- see the README on the question that asks
    # itself. `answering` is set while the whole pipeline re-runs on the answer.
    has clarify_question: str = "";
    has clarify_why: str = "";
    has clarify_reply: str = "";
    has answering: bool = False;

    # The agent's brief (0 or 1), the trail of questions already answered, and
    # what the privacy auditor stripped before anything reached the commons.
    has strategy: list[StrategyView] = [];
    has answered: list[str] = [];
    has privacy_leaks: list[str] = [];
    has activity: list[WalkerTrace] = [];

    # Engine evidence. `engine_calls` is what answers "is that really the model?"
    # without anyone having to take it on trust.
    has engine: str = "";
    has engine_model: str = "";
    has engine_reason: str = "";
    has engine_calls: int = 0;
    has engine_roles: list[str] = [];

    # Refs survive the 3s poll closure so Accept/Dismiss are not overwritten.
    has handled_ref: Ref[list[str]] = Ref([]);
    has ongoing_ref: Ref[list[Suggestion]] = Ref([]);
    has past_ref: Ref[list[Suggestion]] = Ref([]);

    def apply(board: SeekerBoard) -> int;
    async def refresh -> None;
    async def submit -> None;
    async def submit_with(text: str) -> None;
    def use_example(e: MouseEvent) -> None;
    def accept_item(sid: str) -> None;
    def dismiss_item(sid: str) -> None;
    def dismiss_ongoing(sid: str) -> None;
    def toggle_ongoing -> None;
    def go_home(e: MouseEvent) -> None;
    def set_clarify_reply(e: ChangeEvent) -> None;
    async def answer_clarify_yes(e: MouseEvent) -> None;
    async def answer_clarify_no(e: MouseEvent) -> None;
    async def send_clarify_reply -> None;
    async def apply_clarify(ans: str) -> None;

    async can with entry {
        refresh();
    }

    useEffect(lambda {
        timer = setInterval(lambda { refresh(); }, 3000);
        return lambda { clearInterval(timer); };
    }, []);

    if panel == "settings" {
        return <div className="wrap seeker-page">
            <div className="chat-panel">
                <button className="btn ghost sm" type="button" onClick={go_home}>← Back</button>
                <h1 className="chat-heading" style={{"marginTop": "18px"}}>Settings</h1>
                <p className="muted" style={{"marginTop": "8px"}}>
                    Details from signup stay on your private profile.
                </p>
                <div className="card" style={{"marginTop": "18px"}}>
                    <div className="eyebrow">Profile</div>
                    <p style={{"marginTop": "8px"}}>{display_name}</p>
                    <p className="small muted" style={{"marginTop": "6px"}}>Role: person in need</p>
                    {if contact_value {
                        <p className="small muted" key="c" style={{"marginTop": "6px"}}>
                            {(contact_method if contact_method else "contact") + ": " + contact_value}
                        </p>
                    }}
                    {if location {
                        <p className="small muted" key="l" style={{"marginTop": "6px"}}>
                            {"Location: " + location}
                        </p>
                    }}
                </div>
            </div>
        </div>;
    }

    if panel == "past" {
        return <div className="wrap seeker-page">
            <div className="chat-panel">
                <button className="btn ghost sm" type="button" onClick={go_home}>← Back</button>
                <h1 className="chat-heading" style={{"marginTop": "18px"}}>All past suggestions</h1>
                <p className="muted small" style={{"marginTop": "8px", "marginBottom": "18px"}}>
                    Cleared items are kept here so you can revisit them later.
                </p>
                <div className="stack">
                    {if len(past) == 0 {
                        <p className="small muted" key="empty">Nothing cleared yet. Swipe a suggestion left to move it here.</p>
                        skip;
                    }}
                    {for item in past {
                        <SuggestionCard
                            key={item.id}
                            item={item}
                            show_accept={False}
                        />
                    }}
                </div>
            </div>
        </div>;
    }

    return <div className="wrap seeker-page">
        <div className="chat-panel">
            <h1 className="chat-heading">How may you be assisted?</h1>
            <p className="muted small" style={{"marginTop": "8px", "marginBottom": "16px"}}>
                Describe what you need in plain words. Bridge returns programs you may qualify for.
            </p>

            <textarea
                className="field chat-box"
                value={situation}
                placeholder="I need food for me and my two kids this week..."
                onChange={lambda (e: ChangeEvent) { situation = e.target.value; }}
            />

            <div className="row" style={{"marginTop": "12px"}}>
                <button className="btn primary" type="button" onClick={submit} disabled={busy}>
                    {"Finding options..." if busy else "Send request"}
                </button>
                <button className="btn ghost sm" type="button" onClick={use_example}>
                    Use demo request
                </button>
            </div>

            {if error {
                <p className="err" key="e" style={{"marginTop": "10px"}}>{error}</p>
            }}

            {if nudge {
                <div className="card tight" key="n" style={{
                    "borderColor": "var(--ok)",
                    "background": "#141a16",
                    "marginTop": "14px"
                }}>
                    <span className="pill ok"><span className="dot"></span>update</span>
                    <span style={{"marginLeft": "8px", "fontSize": "14px"}}>{nudge}</span>
                </div>
            }}

            {if clarify_question {
                <div className="card tight" key="q" style={{"marginTop": "14px", "borderColor": "var(--cool)"}}>
                    <div className="eyebrow">
                        {"Re-reasoning your plan..." if answering else "One thing would change your plan"}
                    </div>
                    <p style={{"marginTop": "6px"}}>{clarify_question}</p>
                    <p className="small muted">{clarify_why}</p>
                    <div className="row" style={{"marginTop": "12px"}}>
                        <button className="btn cool sm" type="button" onClick={answer_clarify_yes} disabled={busy or answering}>
                            Yes
                        </button>
                        <button className="btn ghost sm" type="button" onClick={answer_clarify_no} disabled={busy or answering}>
                            No
                        </button>
                    </div>
                    <div className="row" style={{"marginTop": "10px", "alignItems": "stretch"}}>
                        <input
                            className="field"
                            style={{"flex": "1"}}
                            value={clarify_reply}
                            placeholder="Or type a short answer..."
                            onChange={set_clarify_reply}
                        />
                        <button className="btn primary sm" type="button" onClick={send_clarify_reply} disabled={busy or answering}>
                            Reply
                        </button>
                    </div>
                </div>
            }}

            <div style={{"marginTop": "22px"}}>
                <OngoingPanel
                    items={ongoing}
                    open={ongoing_open}
                    onToggle={toggle_ongoing}
                    onDismiss={dismiss_ongoing}
                />
            </div>

            {if len(inbox) > 0 {
                <div className="section-title" key="st">
                    Suggested for you
                    <span className="hint">tap to expand · swipe left to clear · accept to track</span>
                </div>
            }}
            <div className="stack" style={{"gap": "10px"}}>
                {for item in inbox {
                    <SuggestionCard
                        key={item.id}
                        item={item}
                        onAccept={accept_item}
                        onDismiss={dismiss_item}
                        show_accept={True}
                    />
                }}
            </div>

            {if len(strategy) > 0 or len(answered) > 0 or len(privacy_leaks) > 0 {
                <div className="section-title" key="wt">
                    Why you are seeing this
                    <span className="hint">
                        the agent's research, what it stripped, and what you have told it
                    </span>
                </div>
            }}
            <div className="stack" style={{"gap": "10px"}}>
                {for (i, brief) in enumerate(strategy) {
                    <StrategyCard key={"sc" + str(i)} brief={brief}/>
                }}
                {if len(answered) > 0 {
                    <AnsweredTrail key="at" rows={answered}/>
                }}
                {if len(privacy_leaks) > 0 {
                    <PrivacyNote key="pn" leaks={privacy_leaks}/>
                }}
                {if len(activity) > 0 {
                    <ActivityFeed key="af" items={activity}/>
                }}
            </div>

            <div className="row" style={{"marginTop": "18px", "justifyContent": "flex-end"}}>
                <EngineBadge
                    mode={engine}
                    model={engine_model}
                    calls={engine_calls}
                    reason={engine_reason}
                    roles={engine_roles}
                />
            </div>
        </div>
    </div>;
}
