"""Bridge - live community directory lookups.

The seeded commons is a fallback. Before eligibility runs, intake pulls real
organisations from OpenStreetMap (Photon place search + Overpass social
facilities) for this person's area, categories, and audience cues (e.g. senior).

Results are upserted onto `root.shared` as `Org` nodes tagged in `notes` with
`source:openstreetmap` so eligibility, broadcast, and the caseworker agent all
see the same graph — no parallel ad-hoc list on the side.
"""

import json;
import urllib.parse;
import urllib.request;
import from core.graph { KeepsTally, Org, OrgTally, now_iso }
import from core.commons { all_orgs, log_walker }
import from core.geo { AREA_CENTROIDS }


glob LIVE_SOURCE_TAG: str = "source:openstreetmap";
glob DIRECTORY_UA: str = "Bridge-Crisis-Navigator/0.1 (crisis-nav demo; local)";


"""Human-readable place name for Photon queries from a 3-digit ZIP prefix."""
def _area_label(zip_prefix: str) -> str {
    if zip_prefix == "941" {
        return "San Francisco California";
    }
    if zip_prefix == "940" {
        return "Daly City California";
    }
    if zip_prefix == "946" {
        return "Oakland California";
    }
    return "San Francisco Bay Area California";
}


"""south, west, north, east box around a seeded service area."""
def _bbox(zip_prefix: str) -> tuple[float, float, float, float] {
    centroid = AREA_CENTROIDS.get(zip_prefix, (37.7749, -122.4194));
    lat = centroid[0];
    lon = centroid[1];
    d = 0.14;
    return (lat - d, lon - d, lat + d, lon + d);
}


"""Whether the person's situation/assets point at older adults."""
def audience_is_senior(situation: str, assets: list[str]) -> bool {
    blob = (situation + " " + " ".join(assets)).lower();
    for cue in [
        "senior", "seniors", "elderly", "elder", "aging", "retiree",
        "retired", "60+", "65+", "older adult", "older adults"
    ] {
        if cue in blob {
            return True;
        }
    }
    return False;
}


"""True when any needle appears in haystack."""
def _has_any(haystack: str, needles: list[str]) -> bool {
    for n in needles {
        if n in haystack {
            return True;
        }
    }
    return False;
}


"""Map an OSM amenity / social_facility tag to Bridge's four categories."""
def _category_for_osm(osm_value: str, name: str, for_whom: str) -> str {
    v = (osm_value + " " + name + " " + for_whom).lower();
    if _has_any(v, ["legal", "eviction", "attorney", "law "]) {
        return "legal";
    }
    if _has_any(v, ["shelter", "homeless", "navigation center", "housing"]) {
        return "shelter";
    }
    if _has_any(v, ["job", "workforce", "career", "employment", "training"]) {
        return "jobs";
    }
    if _has_any(v, [
        "food", "pantry", "meal", "soup", "kitchen", "dining", "senior", "elder"
    ]) {
        return "food";
    }
    if osm_value in ["food_bank", "soup_kitchen", "community_centre", "social_facility"] {
        return "food";
    }
    return "";
}


"""Build Photon search strings from categories + audience."""
def _photon_queries(
    categories: list[str],
    zip_prefix: str,
    senior: bool
) -> list[str] {
    area = _area_label(zip_prefix);
    cats = categories if categories else ["food"];
    out: list[str] = [];
    if senior {
        out = out + [
            "senior meals " + area,
            "Meals on Wheels " + area,
            "senior center " + area,
            "elderly food assistance " + area
        ];
    }
    for cat in cats {
        if cat == "food" {
            out = out + [
                "food bank " + area,
                "food pantry " + area,
                "soup kitchen " + area
            ];
        } elif cat == "shelter" {
            out = out + [
                "homeless shelter " + area,
                "emergency shelter " + area
            ];
        } elif cat == "legal" {
            out = out + [
                "legal aid " + area,
                "eviction defense " + area
            ];
        } elif cat == "jobs" {
            out = out + [
                "job training " + area,
                "workforce center " + area
            ];
        }
    }
    # Dedupe while preserving order.
    seen: list[str] = [];
    for q in out {
        if q not in seen {
            seen = seen + [q];
        }
    }
    return seen[:8];
}


obj LiveOrgHit {
    has name: str;
    has category: str;
    has zip_prefix: str = "";
    has address: str = "";
    has phone: str = "";
    has hours: str = "";
    has notes: str = "";
    has audience: str = "";
    has tier: int = 1;
}


def _photon_hits(query: str, zip_prefix: str, prefer_senior: bool) -> list[LiveOrgHit] {
    hits: list[LiveOrgHit] = [];
    try {
        params = urllib.parse.urlencode({"q": query, "limit": 8, "lang": "en"});
        request = urllib.request.Request(
            "https://photon.komoot.io/api/?" + params,
            headers={"User-Agent": DIRECTORY_UA}
        );
        response = urllib.request.urlopen(request, timeout=10);
        payload = json.loads(response.read().decode("utf-8")) as dict[str, any];
        response.close();
        features = payload["features"] as list[dict[str, any]];
    } except Exception {
        return [];
    }
    for feature in features {
        props = feature["properties"] as dict[str, any];
        name = str(props.get("name", "")).strip();
        if not name {
            continue;
        }
        osm_key = str(props.get("osm_key", ""));
        osm_value = str(props.get("osm_value", ""));
        # Skip pure addresses / businesses with no useful amenity tag when possible.
        if osm_key and osm_key not in ["amenity", "office", "social_facility", "building", "shop"] {
            if "senior" not in name.lower() and "food" not in name.lower() {
                continue;
            }
        }
        for_whom = "";
        cat = _category_for_osm(osm_value, name, for_whom);
        if not cat {
            # Query text is the best hint when OSM tagging is thin.
            ql = query.lower();
            if "legal" in ql or "eviction" in ql {
                cat = "legal";
            } elif "shelter" in ql or "homeless" in ql {
                cat = "shelter";
            } elif "job" in ql or "workforce" in ql {
                cat = "jobs";
            } else {
                cat = "food";
            }
        }
        street = str(props.get("street", ""));
        number = str(props.get("housenumber", ""));
        city = str(props.get("city", props.get("district", "")));
        postcode = str(props.get("postcode", ""));
        addr_bits: list[str] = [];
        line1 = (number + " " + street).strip();
        if line1 {
            addr_bits = addr_bits + [line1];
        }
        if city {
            addr_bits = addr_bits + [city];
        }
        address = ", ".join(addr_bits) if addr_bits else city;
        zpref = postcode[:3] if len(postcode) >= 3 else zip_prefix;
        audience = "";
        nl = name.lower();
        if prefer_senior or "senior" in nl or "elder" in nl {
            audience = "senior";
        }
        phone = str(props.get("phone", props.get("contact:phone", "")));
        hits = hits + [LiveOrgHit(
            name=name,
            category=cat,
            zip_prefix=zpref if zpref else zip_prefix,
            address=address,
            phone=phone,
            hours="",
            notes=f"{LIVE_SOURCE_TAG}; photon query: {query}",
            audience=audience,
            tier=1
        )];
    }
    return hits;
}


def _overpass_hits(zip_prefix: str, prefer_senior: bool) -> list[LiveOrgHit] {
    box = _bbox(zip_prefix);
    south = box[0];
    west = box[1];
    north = box[2];
    east = box[3];
    # Keep the query small — Overpass rate-limits; senior + food are the priority.
    query = (
        "[out:json][timeout:20];("
        + f'nwr["social_facility"="food_bank"]({south},{west},{north},{east});'
        + f'nwr["social_facility"="soup_kitchen"]({south},{west},{north},{east});'
        + f'nwr["amenity"="social_facility"]({south},{west},{north},{east});'
        + f'nwr["amenity"="community_centre"]["name"~"Senior|Elder|Food|Pantry",i]({south},{west},{north},{east});'
        + ");out center tags 35;"
    );
    try {
        encoded = urllib.parse.urlencode({"data": query}).encode("utf-8");
        request = urllib.request.Request(
            "https://overpass-api.de/api/interpreter",
            data=encoded,
            headers={"User-Agent": DIRECTORY_UA},
            method="POST"
        );
        response = urllib.request.urlopen(request, timeout=22);
        payload = json.loads(response.read().decode("utf-8")) as dict[str, any];
        response.close();
        elements = payload.get("elements", []) as list[dict[str, any]];
    } except Exception {
        return [];
    }
    hits: list[LiveOrgHit] = [];
    for el in elements {
        tags = el.get("tags", {}) as dict[str, any];
        name = str(tags.get("name", "")).strip();
        if not name {
            continue;
        }
        for_whom = str(tags.get("social_facility:for", ""));
        osm_value = str(tags.get("social_facility", tags.get("amenity", "")));
        cat = _category_for_osm(osm_value, name, for_whom);
        if not cat {
            continue;
        }
        # When the person is a senior, keep senior-tagged / senior-named sites
        # and general food banks; drop juvenile-only sites.
        fl = for_whom.lower();
        nl = name.lower();
        if prefer_senior {
            if "juvenile" in fl and "senior" not in fl and "senior" not in nl {
                continue;
            }
        }
        audience = "";
        if "senior" in fl or "elderly" in fl or "senior" in nl or "elder" in nl {
            audience = "senior";
        }
        number = str(tags.get("addr:housenumber", ""));
        street = str(tags.get("addr:street", ""));
        city = str(tags.get("addr:city", ""));
        postcode = str(tags.get("addr:postcode", ""));
        line1 = (number + " " + street).strip();
        addr_bits: list[str] = [];
        if line1 {
            addr_bits = addr_bits + [line1];
        }
        if city {
            addr_bits = addr_bits + [city];
        }
        address = ", ".join(addr_bits);
        phone = str(tags.get("phone", tags.get("contact:phone", "")));
        hours = str(tags.get("opening_hours", ""));
        zpref = postcode[:3] if len(postcode) >= 3 else zip_prefix;
        note: str = LIVE_SOURCE_TAG + "; overpass social_facility";
        if for_whom {
            note = note + "; for=" + for_whom;
        }
        hits = hits + [LiveOrgHit(
            name=name,
            category=cat,
            zip_prefix=zpref if zpref else zip_prefix,
            address=address if address else _area_label(zip_prefix),
            phone=phone,
            hours=hours if hours else "Hours vary — call to confirm",
            notes=note,
            audience=audience,
            tier=1
        )];
    }
    return hits;
}


"""Upsert one live hit onto the shared commons. Returns True if new or updated."""
def _upsert_org(hit: LiveOrgHit) -> bool {
    existing: Org | None = None;
    for org in all_orgs() {
        if org.name == hit.name {
            existing = org;
            break;
        }
    }
    audience_note = "";
    if hit.audience {
        audience_note = "; audience:" + hit.audience;
    }
    notes = hit.notes + audience_note;
    if existing is not None {
        # Refresh contact fields from the live directory; keep any richer gates.
        if hit.address {
            existing.address = hit.address;
        }
        if hit.phone and "(555)" not in hit.phone {
            existing.phone = hit.phone;
        }
        if hit.hours {
            existing.hours = hit.hours;
        }
        if LIVE_SOURCE_TAG not in existing.notes {
            existing.notes = (existing.notes + " | " if existing.notes else "") + notes;
        } elif hit.audience and ("audience:" + hit.audience) not in existing.notes {
            existing.notes = existing.notes + audience_note;
        }
        if hit.zip_prefix and not existing.zip_prefix {
            existing.zip_prefix = hit.zip_prefix;
        }
        return True;
    }
    org = root.shared ++> Org(
        name=hit.name,
        category=hit.category,
        zip_prefix=hit.zip_prefix,
        address=hit.address,
        phone=hit.phone,
        hours=hit.hours if hit.hours else "Hours vary — call to confirm",
        notes=notes,
        tier=hit.tier
    );
    grant(org, level=ConnectPerm);
    tally = org +>:KeepsTally:+> OrgTally(
        kind=hit.category,
        updated_at=now_iso()
    );
    grant(tally, level=WritePerm);
    # Live listings rarely publish structured gates; leave Requires empty so
    # eligibility marks them open unless we learn otherwise later.
    return True;
}


"""Pull live orgs for this person into the shared graph. Best-effort, never fatal."""
def sync_live_directory(
    situation: str,
    categories: list[str],
    zip_prefix: str,
    assets: list[str]
) -> int {
    area = zip_prefix if zip_prefix else "941";
    senior = audience_is_senior(situation, assets);
    # If they only said "senior" with no explicit need, still search food —
    # senior meals / congregate dining is the common first resource.
    cats = categories;
    if senior and not cats {
        cats = ["food"];
    }
    collected: list[LiveOrgHit] = [];
    for q in _photon_queries(cats, area, senior) {
        collected = collected + _photon_hits(q, area, senior);
    }
    collected = collected + _overpass_hits(area, senior);

    # Dedupe by name; prefer hits that already have a phone / senior audience.
    by_name: dict[str, LiveOrgHit] = {};
    for hit in collected {
        key = hit.name.strip().lower();
        if not key {
            continue;
        }
        # Restrict to requested categories when we have them.
        if cats and hit.category not in cats {
            # Always keep senior-audience food hits when senior is the cue.
            if not (senior and hit.audience == "senior" and hit.category == "food") {
                continue;
            }
        }
        prev = by_name.get(key);
        if prev is None {
            by_name[key] = hit;
            continue;
        }
        score_new = (2 if hit.phone else 0) + (3 if hit.audience == "senior" and senior else 0) + (1 if hit.address else 0);
        score_old = (2 if prev.phone else 0) + (3 if prev.audience == "senior" and senior else 0) + (1 if prev.address else 0);
        if score_new >= score_old {
            by_name[key] = hit;
        }
    }

    written = 0;
    # Prefer senior-audience rows first so eligibility ranks them earlier.
    ordered = sorted(
        [h for (_, h) in by_name.items()],
        key=lambda (h: LiveOrgHit) -> int {
            return (0 if (senior and h.audience == "senior") else 1);
        }
    );
    for hit in ordered[:24] {
        if _upsert_org(hit) {
            written += 1;
        }
    }
    log_walker(
        "LiveDirectory",
        f"synced {written} real org(s) from OpenStreetMap for area {area}"
        + (" (senior-focused)" if senior else "")
        + f"; categories={', '.join(cats) if cats else 'none'}"
    );
    return written;
}


"""True when the commons already has at least one live (non-demo) org."""
def commons_has_live_orgs -> bool {
    for org in all_orgs() {
        if LIVE_SOURCE_TAG in org.notes {
            return True;
        }
        if org.phone and "(555)" not in org.phone and org.phone.strip() {
            return True;
        }
    }
    return False;
}


"""Demo seed phones look like (415) 555-xxxx — skip when live data is present."""
def is_demo_org(org: Org) -> bool {
    if LIVE_SOURCE_TAG in org.notes {
        return False;
    }
    return "(555)" in org.phone;
}
