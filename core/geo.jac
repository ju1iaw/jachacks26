"""Bridge - turning what the location prompt returns into what the matcher needs.

`orgs_for` filters tier-1 organisations by a 3-digit ZIP prefix, and that prefix
is the only location Bridge is permitted to hold (see `agent.jac`'s
`plan_strategy.zip_prefix`). The signup flow, though, collects location two ways
and neither of them is a prefix:

    "Use my current location"  ->  "37.7749, -122.4194"   (browser geolocation)
    manual entry               ->  "94110" / "Mission District" / "SF"

So the raw string is resolved here, once, on the way into the graph. Nothing
downstream ever sees the coordinates: `IntakeWalker` writes only the prefix onto
the `Person`, which is what reaches the commons.

**Why a table and not a geocoder.** Reverse-geocoding would resolve any point on
earth, but it means shipping the person's precise coordinates to a third party --
which is the one thing the privacy model exists to prevent, and a strange trade to
make for a service area that is three prefixes wide. The commons seeds 941, 940
and 946; a coordinate only has to be resolved against those to be useful, and a
coordinate outside the region resolves to "" rather than to a wrong guess.

**Empty is a real answer.** "" means "no usable location", and callers must treat
it as unknown rather than as a match-anything wildcard -- see the note in
`orgs_for`. Returning a plausible-but-wrong prefix would route someone to a
pantry that will turn them away at the door, which is worse than not filtering.
"""

import math;


"""Approximate centroids of the service areas the commons actually seeds.

Only prefixes that exist on a seeded `Org` belong here. Adding a prefix without a
matching organisation would resolve a coordinate to an area with nothing in it.
"""
glob AREA_CENTROIDS: dict[str, tuple[float, float]] = {
    "941": (37.7749, -122.4194),   # San Francisco proper
    "940": (37.6600, -122.4400),   # Daly City / South SF / Pacifica
    "946": (37.8044, -122.2712)    # Oakland
};

"""Kilometres past which a coordinate is treated as outside the service area.

The seeded areas span roughly 15km end to end, so this is generous on purpose: it
is a sanity bound against resolving Chicago to a San Francisco pantry, not a
catchment radius.
"""
glob AREA_LIMIT_KM: float = 60.0;


"""Great-circle-ish distance in km. Equirectangular is plenty at this scale."""
def _distance_km(lat_a: float, lon_a: float, lat_b: float, lon_b: float) -> float {
    mean_lat = math.radians((lat_a + lat_b) / 2.0);
    dx = math.radians(lon_a - lon_b) * math.cos(mean_lat);
    dy = math.radians(lat_a - lat_b);
    return math.sqrt(dx * dx + dy * dy) * 6371.0;
}


"""Parse "lat, lon" into a coordinate pair, or None if it is not one.

Rejects out-of-range values so that a bare ZIP can never be mistaken for a
latitude -- "94110" alone has no comma and never reaches here, but "941, 10"
would parse as floats and must not survive the range check.
"""
def parse_coords(raw: str) -> tuple[float, float] | None {
    parts = raw.split(",");
    if len(parts) != 2 {
        return None;
    }
    try {
        lat = float(parts[0].strip());
        lon = float(parts[1].strip());
    } except ValueError {
        return None;
    }
    if lat < -90.0 or lat > 90.0 or lon < -180.0 or lon > 180.0 {
        return None;
    }
    # A coordinate pair that is exactly (0, 0) is very much more likely to be a
    # placeholder or a failed read than a person in the Gulf of Guinea.
    if lat == 0.0 and lon == 0.0 {
        return None;
    }
    return (lat, lon);
}


"""Nearest seeded service area to a coordinate, or "" if none is close enough."""
def area_for_coords(lat: float, lon: float) -> str {
    best = "";
    best_km = AREA_LIMIT_KM;
    for (prefix, centroid) in AREA_CENTROIDS.items() {
        km = _distance_km(lat, lon, centroid[0], centroid[1]);
        if km <= best_km {
            best = prefix;
            best_km = km;
        }
    }
    return best;
}


"""The ZIP in a string, as a 3-digit prefix.

Takes the LAST standalone run of exactly five digits, which is what picks the
postcode out of the labels `suggest_addresses` builds:

    "1245 Valencia Street, San Francisco, California, 94110, United States"

A house number is a digit run too, so reading the first one resolves 12345 Main
St to area "123". Photon orders its parts street, city, state, postcode,
country, so the last one is the ZIP. Runs that are not exactly five digits are
skipped rather than truncated -- a 6-digit run is not a ZIP, and treating its
first three as an area is how "Apt 100000" became area "100".
"""
def _prefix_from_digits(raw: str) -> str {
    found = "";
    run = "";
    for ch in raw + " " {
        if ch.isdigit() {
            run += ch;
        } else {
            if len(run) == 5 {
                found = run;
            }
            run = "";
        }
    }
    return found[:3] if found else "";
}


"""Resolve whatever the location step produced into a 3-digit ZIP prefix.

Returns "" when the input cannot be resolved offline -- a city name, a
neighbourhood, a blank, or a coordinate outside the seeded service area. Callers
must read "" as "unknown", never as "anywhere".
"""
def zip_prefix_of(raw: str) -> str {
    text = raw.strip();
    if not text {
        return "";
    }
    coords = parse_coords(text);
    if coords is not None {
        return area_for_coords(coords[0], coords[1]);
    }
    return _prefix_from_digits(text);
}
