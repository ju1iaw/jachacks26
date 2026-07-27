"""Organization console for authoritative receipts, claims, and distributions."""

import from react { useEffect }

sv import from .core.graph {
    NeedCard, OrganizationBoardView, OrganizationTallyView, PledgeCard
}
sv import from .core.walkers {
    OrganizationBoard, OrganizationDistributionWalker,
    OrganizationOccupancyWalker, OrganizationReceiptWalker
}


def:pub OrganizationView -> JsxElement {
    has org_name: str = "Organization";
    has tallies: list[OrganizationTallyView] = [];
    has pending: list[PledgeCard] = [];
    has claims: list[NeedCard] = [];
    has occupancy: str = "0";
    has busy: bool = False;
    has error: str = "";

    async def refresh -> None;
    async def confirm_receipt(pledge_id: str, units: int) -> None;
    async def confirm_distribution(code: str, people: int) -> None;
    async def save_occupancy -> None;

    async can with entry {
        refresh();
    }

    useEffect(lambda {
        timer = setInterval(lambda { refresh(); }, 5000);
        return lambda { clearInterval(timer); };
    }, []);

    return <div className="wrap org-page">
        <div className="org-hero">
            <div>
                <div className="eyebrow">Organization ledger</div>
                <h1>{org_name}</h1>
                <p className="muted">
                    Your confirmations determine what the community still needs.
                </p>
            </div>
            <div className="org-occupancy">
                <label className="small">People currently served</label>
                <div className="row">
                    <input
                        className="field compact"
                        type="number"
                        min="0"
                        value={occupancy}
                        onChange={lambda (e: ChangeEvent) { occupancy = e.target.value; }}
                    />
                    <button className="btn cool sm" type="button" onClick={save_occupancy} disabled={busy}>
                        Save
                    </button>
                </div>
            </div>
        </div>

        {if error {
            <p className="err" key="error">{error}</p>
        }}

        <div className="org-metrics">
            {for tally in tallies {
                <div className="card org-metric" key={tally.kind}>
                    <span className="pill cool">{tally.kind}</span>
                    <strong>{str(tally.needed_from_volunteers)}</strong>
                    <span className="muted small">still needed from volunteers</span>
                    <div className="org-metric-grid">
                        <span><b>{str(tally.received)}</b> received</span>
                        <span><b>{str(tally.reserved)}</b> reserved</span>
                        <span><b>{str(tally.distributed)}</b> distributed</span>
                        <span><b>{str(tally.claims)}</b> claims</span>
                    </div>
                </div>
            }}
        </div>

        <div className="org-work">
            <section>
                <h2>Confirm incoming offers</h2>
                <p className="small muted">Volunteers can offer help; only your team marks what arrived.</p>
                <div className="stack org-list">
                    {if len(pending) == 0 {
                        <p className="card tight muted" key="empty-offers">No offers awaiting receipt.</p>
                        skip;
                    }}
                    {for offer in pending {
                        <div className="card tight" key={offer.pledge_id}>
                            <span className="pill">{offer.kind}</span>
                            <h3>{offer.description}</h3>
                            <p className="small muted">
                                {str(offer.confirmed_units) + " of " + str(offer.capacity) + " received"}
                            </p>
                            <button
                                className="btn primary sm"
                                type="button"
                                disabled={busy}
                                onClick={lambda (e: MouseEvent) {
                                    confirm_receipt(
                                        offer.pledge_id,
                                        offer.capacity - offer.confirmed_units
                                    );
                                }}
                            >
                                Confirm remaining received
                            </button>
                        </div>
                    }}
                </div>
            </section>

            <section>
                <h2>Confirm distributions</h2>
                <p className="small muted">A recipient claim becomes fulfilled only after your confirmation.</p>
                <div className="stack org-list">
                    {if len(claims) == 0 {
                        <p className="card tight muted" key="empty-claims">No reserved needs awaiting distribution.</p>
                        skip;
                    }}
                    {for need in claims {
                        <div className="card tight" key={need.code}>
                            <div className="row">
                                <span className="pill cool">{need.category}</span>
                                <span className="small muted">{need.code}</span>
                            </div>
                            <h3>{need.summary}</h3>
                            <p className="small muted">
                                {"Household " + str(need.household) + " · " + need.status}
                            </p>
                            <button
                                className="btn primary sm"
                                type="button"
                                disabled={busy or need.status != "claimed"}
                                onClick={lambda (e: MouseEvent) {
                                    confirm_distribution(need.code, need.household);
                                }}
                            >
                                {"Waiting for recipient claim" if need.status != "claimed" else "Confirm distributed"}
                            </button>
                        </div>
                    }}
                </div>
            </section>
        </div>
    </div>;
}
