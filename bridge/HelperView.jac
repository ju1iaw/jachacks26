"""Bridge - the view for a volunteer or donor.

This whole screen is built from `NeedCard`s. There is no code path here that
could render a person's name, because the walker behind it returns a type that
has no field to put one in. The volunteer sees a code, a category, a household
size and a 3-digit ZIP - and that is the entire surface area.
"""

import from react { useEffect }
import from .components.Bits { ActivityFeed, EngineBadge, NeedTile, Pill, Stat }

sv import from .core.graph { CommunityView, NeedCard, OrgCard, PledgeCard, WalkerTrace }
sv import from .core.walkers { CommunityBoard, FollowUpWalker, MatchWalker, PledgeWalker }


glob KINDS: list[str] = ["food", "goods", "funds", "time"];


def:pub HelperView(display_name: str) -> JsxElement {
    has needs: list[NeedCard] = [];
    has pledges: list[PledgeCard] = [];
    has orgs: list[OrgCard] = [];
    has activity: list[WalkerTrace] = [];
    has open_count: int = 0;
    has matched_count: int = 0;
    has fulfilled_count: int = 0;
    has engine: str = "";
    has engine_model: str = "";
    has engine_reason: str = "";
    has engine_calls: int = 0;
    has engine_roles: list[str] = [];

    has kind: str = "food";
    has description: str = "";
    has capacity: str = "6";
    has notes: str = "";
    has org_id: str = "";

    has busy: str = "";
    has flash: str = "";

    async def refresh -> None;
    async def add_pledge -> None;
    async def run_match -> None;
    async def run_followup -> None;

    async can with entry {
        refresh();
    }

    useEffect(lambda {
        timer = setInterval(lambda { refresh(); }, 3000);
        return lambda { clearInterval(timer); };
    }, []);

    open_needs = [n for n in needs if n.status == "open"];
    settled = [n for n in needs if n.status != "open"];

    return <div className="wrap">
        <div className="card">
            <div className="row" style={{"justifyContent": "space-between"}}>
                <div>
                    <div className="eyebrow">Community board</div>
                    <h1 style={{"fontSize": "22px", "margin": "8px 0 4px"}}>
                        {"Live needs near you, " + display_name}
                    </h1>
                    <p className="muted small">
                        Every card below is a real, current need routed through a local
                        org. You will never see who it belongs to, and they will never
                        know it was you. Matching runs on its own -- put something on
                        the shelf and Bridge weighs it against every need it can reach,
                        right then.
                    </p>
                </div>
                <EngineBadge
                    mode={engine}
                    model={engine_model}
                    calls={engine_calls}
                    reason={engine_reason}
                    roles={engine_roles}
                />
            </div>
            <div className="stats" style={{"marginTop": "16px"}}>
                <Stat n={open_count} k="open"/>
                <Stat n={matched_count} k="matched"/>
                <Stat n={fulfilled_count} k="fulfilled"/>
            </div>
            <div className="row" style={{"marginTop": "16px"}}>
                <button className="btn" onClick={run_match} disabled={busy != ""}>
                    {"Sweeping..." if busy == "match" else "Re-sweep the commons"}
                </button>
                <button className="btn" onClick={run_followup} disabled={busy != ""}>
                    {"Escalating..." if busy == "follow" else "Simulate 48h with no help"}
                </button>
                {if flash {
                    <span className="small muted" key="f">{flash}</span>
                }}
            </div>
        </div>

        <div className="cols" style={{"marginTop": "22px"}}>
            <div>
                <div className="section-title">
                    Open needs
                    <span className="hint">anonymized at the source, not filtered on the way out</span>
                </div>
                <div className="grid">
                    {if len(open_needs) == 0 {
                        <div className="card empty" key="none">
                            Nothing open right now. When someone asks for help, it lands here.
                        </div>
                        skip;
                    }}
                    {for (i, n) in enumerate(open_needs) {
                        <NeedTile key={str(i)} card={n}/>
                    }}
                </div>

                {if len(settled) > 0 {
                    <div className="section-title" key="st">Matched and fulfilled</div>
                    <div className="grid" key="sg">
                        {for (i, n) in enumerate(settled) {
                            <NeedTile key={str(i)} card={n}/>
                        }}
                    </div>
                }}

                <div className="section-title">
                    On the shelf
                    <span className="hint">matched against reachable needs the moment they land</span>
                </div>
                <div className="grid">
                    {for (i, p) in enumerate(pledges) {
                        <div className="tile" key={str(i)}>
                            <div className="row" style={{"justifyContent": "space-between"}}>
                                <span className="code">{p.kind}</span>
                                <Pill
                                    text={str(p.remaining) + " of " + str(p.capacity) + " left"}
                                    tone={"ok" if p.remaining > 0 else "danger"}
                                />
                            </div>
                            <p className="summary">{p.description}</p>
                            <p className="small muted">{"via " + p.via_org + ("  ·  yours" if p.mine else "")}</p>
                            {if p.notes {
                                <p className="small muted" key="n">{p.notes}</p>
                            }}
                        </div>
                    }}
                </div>
            </div>

            <div className="stack">
                <div className="card">
                    <div className="eyebrow" style={{"marginBottom": "12px"}}>Offer something</div>
                    <label className="lbl">What kind</label>
                    <select
                        className="field"
                        value={kind}
                        onChange={lambda (e: ChangeEvent) { kind = e.target.value; }}
                    >
                        {for (i, k) in enumerate(KINDS) {
                            <option key={str(i)} value={k}>{k}</option>
                        }}
                    </select>

                    <label className="lbl" style={{"marginTop": "12px"}}>What exactly</label>
                    <input
                        className="field"
                        value={description}
                        placeholder="6 ready-to-eat family dinners, delivered"
                        onChange={lambda (e: ChangeEvent) { description = e.target.value; }}
                    />

                    <label className="lbl" style={{"marginTop": "12px"}}>How many units</label>
                    <input
                        className="field"
                        value={capacity}
                        onChange={lambda (e: ChangeEvent) { capacity = e.target.value; }}
                    />

                    <label className="lbl" style={{"marginTop": "12px"}}>Any constraints</label>
                    <input
                        className="field"
                        value={notes}
                        placeholder="Pickup only / I can deliver / weekends"
                        onChange={lambda (e: ChangeEvent) { notes = e.target.value; }}
                    />

                    <label className="lbl" style={{"marginTop": "12px"}}>Route it through</label>
                    <select
                        className="field"
                        value={org_id}
                        onChange={lambda (e: ChangeEvent) { org_id = e.target.value; }}
                    >
                        <option value="">Pick an organisation</option>
                        {for (i, o) in enumerate(orgs) {
                            <option key={str(i)} value={o.org_id}>{o.name}</option>
                        }}
                    </select>

                    <button
                        className="btn cool"
                        style={{"marginTop": "14px", "width": "100%"}}
                        onClick={add_pledge}
                        disabled={busy != ""}
                    >
                        {"Adding..." if busy == "pledge" else "Put it on the shelf"}
                    </button>
                </div>

                <ActivityFeed items={activity}/>
            </div>
        </div>
    </div>;
}
