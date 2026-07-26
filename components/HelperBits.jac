"""Expandable offer cards and need sections for the helper/donor page."""

import from .Bits { NeedTile }

# Types only — core/graph.jac is server-side and compiles to an empty client stub.
sv import from ..core.graph { NeedCard, OfferView }


def:pub OfferCard(
    item: OfferView,
    onRemove: Callable[[str], None] | None = None,
    show_remove: bool = True,
    muted: bool = False
) -> JsxElement {
    has open: bool = False;

    def toggle(e: MouseEvent) -> None {
        open = not open;
    }

    def remove(e: MouseEvent) -> None {
        e.stopPropagation();
        if onRemove {
            onRemove(item.id);
        }
    }

    return <div className={"suggest-card offer-card" + (" muted-card" if muted else "")}>
        <button className="suggest-head" type="button" onClick={toggle}>
            <div className="suggest-head-text">
                <span className="pill cool">{item.kind if item.kind else "offer"}</span>
                <h3>{item.name}</h3>
            </div>
            <span className={"chev " + ("up" if open else "down")} aria-hidden="true">⌃</span>
        </button>
        {if open {
            <div className="suggest-body" key="body">
                {if item.description {
                    <p className="suggest-desc" key="d">{item.description}</p>
                }}
                {if len(item.details) > 0 {
                    <ol className="suggest-steps" key="s">
                        {for (i, line) in enumerate(item.details) {
                            <li key={str(i)}><span>{line}</span></li>
                        }}
                    </ol>
                }}
                {if item.notes {
                    <p className="small muted" key="n" style={{"marginTop": "10px"}}>{item.notes}</p>
                }}
                {if show_remove and onRemove {
                    <div className="suggest-actions" key="a">
                        <button className="btn ghost sm" type="button" onClick={remove}>
                            Remove
                        </button>
                    </div>
                }}
            </div>
        }}
    </div>;
}


def:pub NeedSection(
    title: str,
    active: list[NeedCard],
    completed: list[NeedCard],
    badge: int = 0,
    empty_msg: str = "Nothing here yet."
) -> JsxElement {
    has show_completed: bool = False;

    def toggle_completed(e: MouseEvent) -> None {
        show_completed = not show_completed;
    }

    return <div className="need-section">
        <div className="need-section-head">
            <h2 className="need-section-title">{title}</h2>
            {if badge > 0 {
                <span className="notif-badge" key="b">{str(badge)}</span>
            }}
        </div>

        <div className="stack" style={{"gap": "10px"}}>
            {if len(active) == 0 {
                <p className="small muted" key="empty">{empty_msg}</p>
                skip;
            }}
            {for (i, n) in enumerate(active) {
                <div key={n.code + "-" + str(i)}>
                    {if n.via_org {
                        <p className="org-label" key="o">{n.via_org}</p>
                    }}
                    <NeedTile card={n}/>
                </div>
            }}
        </div>

        {if len(completed) > 0 {
            <div key="done" style={{"marginTop": "12px"}}>
                <button className="show-completed" type="button" onClick={toggle_completed}>
                    {( "Hide completed" if show_completed else "Show completed" )
                        + " (" + str(len(completed)) + ")"}
                    <span className={"chev " + ("up" if show_completed else "down")} aria-hidden="true">⌃</span>
                </button>
                {if show_completed {
                    <div className="stack completed-stack" key="list" style={{"gap": "10px", "marginTop": "10px"}}>
                        {for (i, n) in enumerate(completed) {
                            <div className="completed-wrap" key={n.code + "-c-" + str(i)}>
                                <NeedTile card={n}/>
                            </div>
                        }}
                    </div>
                }}
            </div>
        }}
    </div>;
}


def:pub OffersPanel(
    active: list[OfferView],
    past: list[OfferView],
    show_past: bool,
    onRemove: Callable[[str], None],
    onTogglePast: Callable[[], None]
) -> JsxElement {
    def toggle(e: MouseEvent) -> None {
        onTogglePast();
    }

    return <div className="offers-panel card">
        <div className="eyebrow">Offered services / goods</div>
        <p className="small muted" style={{"marginTop": "6px", "marginBottom": "14px"}}>
            Things you said you can provide. Expand for details; remove anytime.
        </p>
        <div className="stack" style={{"gap": "10px"}}>
            {if len(active) == 0 {
                <p className="small muted" key="none">No active offers yet. Tell Bridge how you can help.</p>
                skip;
            }}
            {for item in active {
                <OfferCard key={item.id} item={item} onRemove={onRemove} show_remove={True}/>
            }}
        </div>

        <button className="show-completed" type="button" style={{"marginTop": "16px"}} onClick={toggle}>
            {( "Hide all past offers" if show_past else "All past offers" )
                + ("" if len(past) == 0 else " (" + str(len(past)) + ")")}
            <span className={"chev " + ("up" if show_past else "down")} aria-hidden="true">⌃</span>
        </button>
        {if show_past {
            <div className="stack" key="past" style={{"gap": "10px", "marginTop": "10px"}}>
                {if len(past) == 0 {
                    <p className="small muted" key="empty">No removed offers yet.</p>
                    skip;
                }}
                {for item in past {
                    <OfferCard
                        key={item.id}
                        item={item}
                        show_remove={False}
                        muted={True}
                    />
                }}
            </div>
        }}
    </div>;
}
