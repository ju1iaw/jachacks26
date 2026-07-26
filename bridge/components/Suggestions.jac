"""Expandable assistance suggestions for the seeker chat page.

Each card starts collapsed to a name. Expanding reveals a short description and
simple action steps with links. Swipe left (or the accept control) moves the
item into Past or Ongoing respectively.
"""


obj ActionStep {
    has text: str;
    has link: str = "";
    has link_label: str = "";
}


obj Suggestion {
    has id: str;
    has name: str;
    has description: str = "";
    has steps: list[ActionStep] = [];
    has kind: str = "program";
    has badge: str = "";
}


"""Build a few fake but realistic program cards for the demo path."""
def:pub demo_suggestions -> list[Suggestion] {
    return [
        Suggestion(
            id="demo-senior-food",
            name="Second Harvest Senior Food Assistance",
            description="Monthly food box for adults 60+. Delivery available in your ZIP if you cannot travel.",
            steps=[
                ActionStep(
                    text="Use this link to apply for assistance. Required documents: ID",
                    link="https://example.com/second-harvest/senior",
                    link_label="Apply online"
                ),
                ActionStep(
                    text="Call if you need help filling the form.",
                    link="tel:5550100200",
                    link_label="(555) 010-0200"
                )
            ]
        ),
        Suggestion(
            id="demo-id-replace",
            name="County ID Replacement Desk",
            description="Same-day temporary ID if you lost yours. No appointment needed before 2pm.",
            steps=[
                ActionStep(
                    text="Bring any mail with your name on it, or a sworn statement form.",
                    link="https://example.com/county/id-replace",
                    link_label="Print the statement form"
                ),
                ActionStep(
                    text="Go to 1 Dr. Carlton B. Goodlett Pl, Window 3. Open Mon–Fri 9–4."
                )
            ]
        ),
        Suggestion(
            id="demo-eviction",
            name="Legal Aid Eviction Defense",
            description="Free counsel if you have an eviction notice. Same-week intake for active notices.",
            steps=[
                ActionStep(
                    text="Upload your eviction notice and start intake.",
                    link="https://example.com/legal-aid/intake",
                    link_label="Start intake"
                ),
                ActionStep(
                    text="Required documents: eviction notice, photo ID if you have one."
                )
            ]
        )
    ];
}


def:pub SuggestionCard(
    item: Suggestion,
    onAccept: Callable[[str], None] | None = None,
    onDismiss: Callable[[str], None] | None = None,
    show_accept: bool = True
) -> JsxElement {
    has open: bool = False;
    has drag_x: float = 0.0;
    has dragging: bool = False;
    has start_x: float = 0.0;
    has dismissing: bool = False;

    def event_x(e: any) -> float {
        touches = e.touches;
        if touches and len(touches) > 0 {
            return touches[0].clientX;
        }
        changed = e.changedTouches;
        if changed and len(changed) > 0 {
            return changed[0].clientX;
        }
        return e.clientX;
    }

    def toggle(e: MouseEvent) -> None {
        if dragging or drag_x < -8.0 or drag_x > 8.0 {
            return;
        }
        open = not open;
    }

    def accept(e: MouseEvent) -> None {
        e.stopPropagation();
        if onAccept {
            onAccept(item.id);
        }
    }

    def pointer_down(e: any) -> None {
        start_x = event_x(e);
        dragging = True;
    }

    def pointer_move(e: any) -> None {
        if not dragging {
            return;
        }
        dx = event_x(e) - start_x;
        # Only allow swipe left (clear).
        drag_x = dx if dx < 0.0 else 0.0;
    }

    def pointer_up(e: any) -> None {
        if not dragging {
            return;
        }
        dragging = False;
        if drag_x < -88.0 {
            dismissing = True;
            if onDismiss {
                onDismiss(item.id);
            }
            return;
        }
        drag_x = 0.0;
    }

    kind_pill = item.badge if item.badge else ("helper offer" if item.kind == "helper" else "program");
    kind_tone = "cool" if item.kind == "helper" else ("danger" if item.kind == "blocked" else "warm");

    card_class = "suggest-card";
    if dragging {
        card_class = card_class + " dragging";
    }
    if dismissing {
        card_class = card_class + " dismissing";
    }

    style_map: dict[str, str] = {
        "transform": "translateX(" + str(int(drag_x)) + "px)"
    };

    return <div className="suggest-track">
        <div className="suggest-rail" aria-hidden="true">Clear</div>
        <div
            className={card_class}
            style={style_map}
            onMouseDown={pointer_down}
            onMouseMove={pointer_move}
            onMouseUp={pointer_up}
            onMouseLeave={pointer_up}
            onTouchStart={pointer_down}
            onTouchMove={pointer_move}
            onTouchEnd={pointer_up}
        >
            <button className="suggest-head" type="button" onClick={toggle}>
                <div className="suggest-head-text">
                    <span className={"pill " + kind_tone}>{kind_pill}</span>
                    <h3>{item.name}</h3>
                </div>
                <span className={"chev " + ("up" if open else "down")} aria-hidden="true">⌃</span>
            </button>

            {if open {
                <div className="suggest-body" key="body">
                    {if item.description {
                        <p className="suggest-desc" key="d">{item.description}</p>
                    }}
                    <ol className="suggest-steps">
                        {for (i, step) in enumerate(item.steps) {
                            <li key={str(i)}>
                                <span>{step.text}</span>
                                {if step.link {
                                    <a
                                        key="l"
                                        className="suggest-link"
                                        href={step.link}
                                        target="_blank"
                                        rel="noreferrer"
                                        onClick={lambda (e: MouseEvent) { e.stopPropagation(); }}
                                    >
                                        {step.link_label if step.link_label else step.link}
                                    </a>
                                }}
                            </li>
                        }}
                    </ol>
                    {if show_accept and onAccept {
                        <div className="suggest-actions" key="a">
                            <button className="btn primary sm" type="button" onClick={accept}>
                                Accept
                            </button>
                        </div>
                    }}
                </div>
            }}
        </div>
    </div>;
}


def:pub OngoingPanel(
    items: list[Suggestion],
    open: bool,
    onToggle: Callable[[], None],
    onDismiss: Callable[[str], None]
) -> JsxElement {
    def handle_toggle(e: MouseEvent) -> None {
        onToggle();
    }

    return <div className="ongoing">
        <button className="ongoing-toggle" type="button" onClick={handle_toggle}>
            <span className="ongoing-label">
                Ongoing
                {if len(items) > 0 {
                    <span className="ongoing-count" key="c">{str(len(items))}</span>
                }}
            </span>
            <span className={"chev " + ("up" if open else "down")} aria-hidden="true">⌃</span>
        </button>
        {if open {
            <div className="stack" key="list" style={{"gap": "10px", "marginTop": "10px"}}>
                {if len(items) == 0 {
                    <p className="small muted" key="empty">
                        Accepted programs and helper offers you have not finished yet will show up here.
                    </p>
                    skip;
                }}
                {for item in items {
                    <SuggestionCard
                        key={item.id}
                        item={item}
                        onDismiss={onDismiss}
                        show_accept={False}
                    />
                }}
            </div>
        }}
    </div>;
}
