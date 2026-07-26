"""Bridge - helper / volunteer page.

Chat: "How can you help?" extracts offered services into the right rail.
Left: matched individual needs (with incomplete badge) and needs by organization,
each with a gray "show completed" fold.
"""

import from react { useEffect }
import from .components.HelperBits { NeedSection, OffersPanel }

sv import from .core.graph { NeedCard, OrgCard, PledgeCard }
sv import from .core.walkers {
    CommunityBoard, HelperOfferWalker, MatchWalker, RetirePledgeWalker
}


# Client constructor. Same shape as core/graph.OfferView (server reports);
# graph.jac does not compile onto the client, so the UI needs its own copy.
obj OfferView {
    has id: str;
    has name: str;
    has kind: str = "time";
    has description: str = "";
    has details: list[str] = [];
    has notes: str = "";
    has pledge_id: str = "";
}


def offer_from_pledge(p: PledgeCard) -> OfferView {
    name = p.description;
    parts = p.description.split(":");
    if len(parts) > 1 {
        name = parts[0].strip();
    }
    details: list[str] = [];
    if p.notes {
        for part in p.notes.split(" | ") {
            if part.strip() {
                details = details + [part.strip()];
            }
        }
    }
    return OfferView(
        id="pledge-" + p.pledge_id[-10:],
        name=name,
        kind=p.kind,
        description=p.description,
        details=details,
        notes=("via " + p.via_org) if p.via_org else "",
        pledge_id=p.pledge_id
    );
}


def demo_helper_offers -> list[OfferView] {
    return [
        OfferView(
            id="demo-meal",
            name="Meal cooking and delivery",
            kind="food",
            description="Home-cooked meals delivered to households nearby.",
            details=[
                "Can cook for a household of up to 4",
                "Delivery within about 10 miles",
                "Evenings and weekends preferred"
            ],
            notes="Delivery radius ~10 miles"
        )
    ];
}


def:pub HelperView(display_name: str) -> JsxElement {
    has needs: list[NeedCard] = [];
    has orgs: list[OrgCard] = [];
    has offer_text: str = "";
    has offers: list[OfferView] = [];
    has past_offers: list[OfferView] = [];
    has show_past: bool = False;
    has chat_reply: str = "";
    has busy: bool = False;
    has error: str = "";

    has offers_ref: Ref[list[OfferView]] = Ref([]);
    has past_ref: Ref[list[OfferView]] = Ref([]);
    has known_ref: Ref[list[str]] = Ref([]);

    async def refresh -> None;
    async def submit_offer -> None;
    async def remove_offer(oid: str) -> None;
    def toggle_past -> None;

    async can with entry {
        refresh();
    }

    useEffect(lambda {
        timer = setInterval(lambda { refresh(); }, 4000);
        return lambda { clearInterval(timer); };
    }, []);

    matched_active = [n for n in needs if n.status == "matched"];
    matched_done = [n for n in needs if n.status == "fulfilled"];
    org_active = [n for n in needs if n.status == "open"];
    org_done = [n for n in needs if n.status == "fulfilled"];

    return <div className="wrap helper-page">
        <div className="helper-chat">
            <h1 className="chat-heading">How can you help?</h1>
            <p className="muted small" style={{"marginTop": "8px", "marginBottom": "16px"}}>
                {"Describe what you can offer, " + display_name + ". Bridge will turn it into clear offers on the right."}
            </p>
            <textarea
                className="field chat-box"
                value={offer_text}
                placeholder="I can cook a meal for someone and deliver within 10 miles..."
                onChange={lambda (e: ChangeEvent) { offer_text = e.target.value; }}
            />
            <div className="row" style={{"marginTop": "12px"}}>
                <button className="btn cool" type="button" onClick={submit_offer} disabled={busy}>
                    {"Finding how you can help..." if busy else "Send"}
                </button>
            </div>
            {if error {
                <p className="err" key="e" style={{"marginTop": "10px"}}>{error}</p>
            }}
            {if chat_reply {
                <div className="card tight" key="r" style={{"marginTop": "14px"}}>
                    <p>{chat_reply}</p>
                </div>
            }}
        </div>

        <div className="helper-cols" style={{"marginTop": "28px"}}>
            <div className="helper-left stack" style={{"gap": "22px"}}>
                <NeedSection
                    title="Matched Individual Needs"
                    active={matched_active}
                    completed={matched_done}
                    badge={len(matched_active)}
                    empty_msg="No incomplete matches yet. When your offers fit a need, they show up here."
                />
                <NeedSection
                    title="By organization"
                    active={org_active}
                    completed={org_done}
                    badge={0}
                    empty_msg="No open needs routed through local organizations right now."
                />
            </div>

            <div className="helper-right">
                <OffersPanel
                    active={offers}
                    past={past_offers}
                    show_past={show_past}
                    onRemove={remove_offer}
                    onTogglePast={toggle_past}
                />
            </div>
        </div>
    </div>;
}
