"""Bridge - accounts and the shared commons.

Two things live here:

  * **Accounts.** A logged-in user is either a `seeker` (person in need) or a
    `helper` (volunteer/donor). The role is an `Account` node on their own root,
    and it decides which of the two views they get.

  * **The commons.** `root.shared` holds every `Org`, `Requirement`,
    `Contribution` and `Need` -- the things both sides must see. Private
    identity (`Person`, `Donor`) never goes here.
"""

import from core.graph {
    Account, Activity, Contribution, Donor, Need, Org, OrgCard, Person,
    PledgeCard, Requirement, Seeded, WalkerTrace, AccountView, EngineReport,
    RoutedThrough, Pledges, Requires,
    now_iso
}
import from core.reason {
    drain_degrade_log, engine, engine_state, ensure_engine, role_calls
}


glob SEED_VERSION: str = "bridge-2026-07-1";
glob ACTIVITY_CAP: int = 60;


# ---------------------------------------------------------------------------
# Accounts
# ---------------------------------------------------------------------------

def _my_account -> Account | None {
    found = [root --> [?:Account]];
    return found[0] if found else None;
}


"""A display-ready tally of how many times each LLM role has actually fired."""
def role_tally -> list[str] {
    return [f"{name} x{count}" for (name, count) in sorted(role_calls().items())];
}


"""What is answering questions right now. Rendered as a badge in both views."""
def engine_report -> EngineReport {
    st = engine_state();
    return EngineReport(
        mode=st.mode,
        model=st.model,
        reason=st.reason,
        calls=st.calls,
        failures=st.failures,
        fallbacks=st.fallbacks,
        roles=role_tally()
    );
}


"""Drain reason.jac's pending degradation lines into the shared Activity feed.

`reason.jac` cannot import this module (this module imports it), so it buffers
degradation events in a list and callers move them onto the graph. Any walker
that touches the model should call this on the way out, so a silent fallback
becomes a visible line in the UI.
"""
def flush_engine_log {
    for line in drain_degrade_log() {
        log_walker("engine", line);
    }
}


def:protect me -> AccountView {
    ensure_engine();
    rep = engine_report();
    acct = _my_account();
    return AccountView(
        role=acct.role if acct is not None else "",
        display_name=acct.display_name if acct is not None else "",
        engine=rep.mode,
        engine_model=rep.model,
        engine_reason=rep.reason,
        engine_calls=rep.calls,
        engine_fallbacks=rep.fallbacks,
        engine_roles=rep.roles
    );
}


"""Claim a side of Bridge. Called once, right after signup."""
def:protect choose_role(role: str, display_name: str) -> AccountView {
    clean = role if role in ["seeker", "helper"] else "seeker";
    acct = _my_account();
    if acct is None {
        acct = root ++> Account(role=clean, display_name=display_name);
    } else {
        acct.role = clean;
        acct.display_name = display_name;
    }
    ensure_commons();
    if clean == "helper" and not [root --> [?:Donor]] {
        root ++> Donor(name=display_name);
    }
    rep = engine_report();
    return AccountView(
        role=acct.role,
        display_name=acct.display_name,
        engine=rep.mode,
        engine_model=rep.model,
        engine_reason=rep.reason,
        engine_calls=rep.calls,
        engine_fallbacks=rep.fallbacks,
        engine_roles=rep.roles
    );
}


# ---------------------------------------------------------------------------
# The live walker log
# ---------------------------------------------------------------------------

"""Append one line to the shared activity feed both views render."""
def log_walker(by_walker: str, detail: str) {
    existing = [root.shared --> [?:Activity]];
    entry = root.shared ++> Activity(
        walker=by_walker,
        detail=detail,
        at=now_iso(),
        seq=len(existing) + 1
    );
    grant(entry, level=ReadPerm);
    if len(existing) > ACTIVITY_CAP {
        ranked = sorted(existing, key=lambda (a: Activity) -> int { return a.seq; });
        for stale in ranked[:len(existing) - ACTIVITY_CAP] {
            del stale;
        }
    }
}


def recent_activity(limit: int) -> list[WalkerTrace] {
    entries = sorted(
        [root.shared --> [?:Activity]],
        key=lambda (a: Activity) -> int { return a.seq; },
        reverse=True
    );
    return [
        WalkerTrace(walker=a.walker, detail=a.detail, at=a.at)
        for a in entries[:limit]
    ];
}


# ---------------------------------------------------------------------------
# Commons readers
# ---------------------------------------------------------------------------

def all_orgs -> list[Org] {
    return [root.shared --> [?:Org]];
}


def orgs_for(category: str, zip_prefix: str, max_tier: int) -> list[Org] {
    hits: list[Org] = [];
    for org in all_orgs() {
        if org.category != category {
            continue;
        }
        if org.tier > max_tier {
            continue;
        }
        if zip_prefix and org.tier == 1 and org.zip_prefix != zip_prefix {
            continue;
        }
        hits.append(org);
    }
    return hits;
}


def org_cards -> list[OrgCard] {
    cards: list[OrgCard] = [];
    for org in all_orgs() {
        cards.append(OrgCard(
            org_id=jid(org),
            name=org.name,
            category=org.category,
            address=org.address,
            phone=org.phone,
            hours=org.hours,
            tier=org.tier,
            requirements=[r.label for r in [org ->:Requires:->]]
        ));
    }
    return cards;
}


def pledge_cards -> list[PledgeCard] {
    mine: list[str] = [];
    for donor in [root --> [?:Donor]] {
        mine = mine + [jid(c) for c in [donor ->:Pledges:->]];
    }
    cards: list[PledgeCard] = [];
    for c in [root.shared --> [?:Contribution]] {
        via = [o.name for o in [c ->:RoutedThrough:->]];
        cards.append(PledgeCard(
            pledge_id=jid(c),
            kind=c.kind,
            description=c.description,
            capacity=c.capacity,
            remaining=c.remaining,
            via_org=via[0] if via else "unrouted",
            notes=c.notes,
            mine=jid(c) in mine
        ));
    }
    return cards;
}


# ---------------------------------------------------------------------------
# Seeding the commons
# ---------------------------------------------------------------------------

obj ReqSpec {
    has label: str;
    has kind: str;
    has workaround: str;
}

obj OrgSpec {
    has name: str;
    has category: str;
    has zip_prefix: str;
    has address: str;
    has phone: str;
    has hours: str;
    has tier: int;
    has notes: str;
    has reqs: list[ReqSpec];
}

obj PledgeSpec {
    has kind: str;
    has description: str;
    has capacity: int;
    has notes: str;
    has org: str;
}


glob SEED_ORGS: list[OrgSpec] = [
    OrgSpec(
        name="Mission Community Food Bank",
        category="food",
        zip_prefix="941",
        address="1245 Valencia St, San Francisco",
        phone="(415) 555-0142",
        hours="Tue & Thu, 9am-1pm",
        tier=1,
        notes="Largest weekly distribution in the district.",
        reqs=[
            ReqSpec(
                label="Government-issued photo ID",
                kind="document",
                workaround="Get a free California ID at the DMV on Fell St -- fee waived with a shelter or clinic letter, same day."
            ),
            ReqSpec(
                label="Proof of address in the 941 service area",
                kind="residency",
                workaround="A piece of mail, a lease, or a signed letter from a shelter all count."
            )
        ]
    ),
    OrgSpec(
        name="Bayview Free Pantry",
        category="food",
        zip_prefix="941",
        address="1601 Newcomb Ave, San Francisco",
        phone="(415) 555-0177",
        hours="Wed 10am-4pm, Sat 9am-noon",
        tier=1,
        notes="No-barrier pantry. No ID, no paperwork, no questions.",
        reqs=[]
    ),
    OrgSpec(
        name="SF-Marin Food Bank Home Delivery",
        category="food",
        zip_prefix="940",
        address="900 Pennsylvania Ave, San Francisco",
        phone="(415) 555-0198",
        hours="Deliveries Mon-Fri",
        tier=2,
        notes="Brings groceries to the door -- built for households with no transport.",
        reqs=[
            ReqSpec(
                label="A phone number they can confirm delivery on",
                kind="document",
                workaround="A friend's or shelter's phone number is accepted."
            ),
            ReqSpec(
                label="Booked delivery slot",
                kind="appointment",
                workaround="Call (415) 555-0198 -- slots open Monday morning for the week."
            )
        ]
    ),
    OrgSpec(
        name="ECS Navigation Center",
        category="shelter",
        zip_prefix="941",
        address="680 Bryant St, San Francisco",
        phone="(415) 555-0110",
        hours="Intake 24/7",
        tier=1,
        notes="Walk-in intake, families kept together, pets allowed.",
        reqs=[]
    ),
    OrgSpec(
        name="Hamilton Families Shelter Access",
        category="shelter",
        zip_prefix="941",
        address="260 Golden Gate Ave, San Francisco",
        phone="(415) 555-0123",
        hours="Mon-Fri 8am-5pm",
        tier=1,
        notes="Family-only shelter with a dedicated housing case manager.",
        reqs=[
            ReqSpec(
                label="Intake appointment booked in advance",
                kind="appointment",
                workaround="Call the access line at 8am -- same-day slots are released first thing."
            ),
            ReqSpec(
                label="Proof of address in the 941 service area",
                kind="residency",
                workaround="A shelter letter or any local mail is enough."
            )
        ]
    ),
    OrgSpec(
        name="Eviction Defense Collaborative",
        category="legal",
        zip_prefix="941",
        address="1338 Mission St, San Francisco",
        phone="(415) 555-0166",
        hours="Drop-in Mon-Thu 9am-noon",
        tier=1,
        notes="Free representation for tenants with an active case.",
        reqs=[
            ReqSpec(
                label="A copy of the eviction notice or court summons",
                kind="document",
                workaround="A clear phone photo of the notice is accepted -- bring it on your phone."
            )
        ]
    ),
    OrgSpec(
        name="Bay Area Legal Aid",
        category="legal",
        zip_prefix="941",
        address="1735 Telegraph Ave, Oakland",
        phone="(415) 555-0154",
        hours="Hotline Mon-Fri 9am-3pm",
        tier=2,
        notes="Phone intake, no office visit needed.",
        reqs=[
            ReqSpec(
                label="Household income under 125% of the federal poverty line",
                kind="income",
                workaround="Self-declared on the call -- no pay stubs needed up front."
            )
        ]
    ),
    OrgSpec(
        name="Goodwill Career Center",
        category="jobs",
        zip_prefix="941",
        address="1500 Mission St, San Francisco",
        phone="(415) 555-0188",
        hours="Mon-Fri 9am-5pm",
        tier=1,
        notes="Same-week placement into warehouse and retail roles.",
        reqs=[]
    ),
    OrgSpec(
        name="OEWD Workforce Center",
        category="jobs",
        zip_prefix="941",
        address="3120 Mission St, San Francisco",
        phone="(415) 555-0131",
        hours="Mon-Fri 8:30am-4:30pm",
        tier=1,
        notes="Paid training placements, but the onboarding paperwork is real.",
        reqs=[
            ReqSpec(
                label="Social security card",
                kind="document",
                workaround="Request a replacement free at the SSA office on Golden Gate Ave -- arrives in 10 days."
            ),
            ReqSpec(
                label="Government-issued photo ID",
                kind="document",
                workaround="Get a free California ID at the DMV on Fell St -- fee waived with a shelter or clinic letter, same day."
            )
        ]
    )
];

glob SEED_WIDE_ORGS: list[OrgSpec] = [
    OrgSpec(
        name="Compass Family Shelter Hotline",
        category="shelter",
        zip_prefix="940",
        address="Phone intake, citywide",
        phone="(415) 555-0201",
        hours="Daily 8am-8pm",
        tier=2,
        notes="Regional family placement -- covers the whole peninsula.",
        reqs=[]
    ),
    OrgSpec(
        name="Bay Area Community Services",
        category="shelter",
        zip_prefix="",
        address="Regional, multi-county",
        phone="(510) 555-0233",
        hours="Mon-Fri 9am-6pm",
        tier=3,
        notes="Last-resort regional placement when local beds are full.",
        reqs=[]
    ),
    OrgSpec(
        name="Alameda County Community Food Bank",
        category="food",
        zip_prefix="946",
        address="7900 Edgewater Dr, Oakland",
        phone="(510) 555-0244",
        hours="Mon-Fri 9am-4pm",
        tier=3,
        notes="Cross-bay distribution network, ships to partner sites.",
        reqs=[]
    ),
    OrgSpec(
        name="JobTrain Regional",
        category="jobs",
        zip_prefix="940",
        address="1200 O'Brien Dr, Menlo Park",
        phone="(650) 555-0255",
        hours="Mon-Fri 8am-5pm",
        tier=2,
        notes="Free vocational training with a stipend.",
        reqs=[]
    ),
    OrgSpec(
        name="Legal Aid at Work",
        category="legal",
        zip_prefix="",
        address="Statewide hotline",
        phone="(866) 555-0266",
        hours="Tue & Thu 10am-2pm",
        tier=3,
        notes="Employment and benefits law, phone only.",
        reqs=[]
    )
];

glob SEED_PLEDGES: list[PledgeSpec] = [
    PledgeSpec(
        kind="food",
        description="12 ready-to-eat family meal boxes, no cooking needed",
        capacity=12,
        notes="Dropped at the pantry every Wednesday. Can be delivered.",
        org="Bayview Free Pantry"
    ),
    PledgeSpec(
        kind="food",
        description="40lb of dry rice, beans and pasta",
        capacity=8,
        notes="Bulk staples, pickup only.",
        org="Mission Community Food Bank"
    )
];


"""Plant the orgs, their real eligibility gates, and a couple of standing pledges."""
def ensure_commons -> bool {
    if [root.shared --> [?:Seeded, version == SEED_VERSION]] {
        return False;
    }

    for spec in SEED_ORGS + SEED_WIDE_ORGS {
        org = root.shared ++> Org(
            name=spec.name,
            category=spec.category,
            zip_prefix=spec.zip_prefix,
            address=spec.address,
            phone=spec.phone,
            hours=spec.hours,
            notes=spec.notes,
            tier=spec.tier
        );
        grant(org, level=ConnectPerm);
        for req in spec.reqs {
            gate = org +>:Requires:+> Requirement(
                label=req.label,
                kind=req.kind,
                workaround=req.workaround
            );
            grant(gate, level=ReadPerm);
        }
    }

    by_name: dict[str, Org] = {};
    for org in all_orgs() {
        by_name[org.name] = org;
    }
    for pspec in SEED_PLEDGES {
        pledge = root.shared ++> Contribution(
            kind=pspec.kind,
            description=pspec.description,
            capacity=pspec.capacity,
            remaining=pspec.capacity,
            notes=pspec.notes
        );
        grant(pledge, level=WritePerm);
        host = by_name.get(pspec.org);
        if host is not None {
            pledge +>:RoutedThrough:+> host;
        }
    }

    marker = root.shared ++> Seeded(version=SEED_VERSION);
    grant(marker, level=ReadPerm);
    log_walker(
        "ensure_commons",
        f"planted {len(SEED_ORGS) + len(SEED_WIDE_ORGS)} orgs and {len(SEED_PLEDGES)} standing pledges"
    );
    return True;
}


def:pub bootstrap -> str {
    fresh = ensure_commons();
    return "seeded" if fresh else "already-seeded";
}
