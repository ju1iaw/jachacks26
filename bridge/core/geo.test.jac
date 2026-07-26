"""Tests for the location resolver.

    jac test core/geo.test.jac

This module decides what location Bridge holds about a person, so both
directions of failure get a test: a coordinate that should resolve to a service
area, and one that must NOT resolve to a plausible-looking wrong one.
"""


# A `.test.jac` annex of core/geo.jac -- that module is already in scope.


test "browser geolocation in San Francisco resolves to the 941 service area" {
    assert zip_prefix_of("37.7749, -122.4194") == "941";
}


test "geolocation across the bay resolves to Oakland, not San Francisco" {
    assert zip_prefix_of("37.8044, -122.2712") == "946";
}


test "the format the Gate actually writes is what the resolver accepts" {
    # Gate.impl.jac builds this string by concatenating the two coords with ", ".
    lat = 37.7749;
    lon = -122.4194;
    assert zip_prefix_of(str(lat) + ", " + str(lon)) == "941";
}


test "a coordinate outside the service area resolves to unknown, not a guess" {
    # Chicago. The nearest seeded centroid is ~2900km away; returning "941" here
    # would route someone to a pantry that will turn them away at the door.
    assert zip_prefix_of("41.8781, -87.6298") == "";
}


test "a manually typed ZIP becomes its 3-digit prefix" {
    assert zip_prefix_of("94110") == "941";
    assert zip_prefix_of("  94110  ") == "941";
}


test "a ZIP embedded in a longer line is still found" {
    assert zip_prefix_of("Mission District, San Francisco 94110") == "941";
}


test "a city name with no ZIP is unknown rather than wrong" {
    assert zip_prefix_of("Mission District") == "";
    assert zip_prefix_of("San Francisco") == "";
}


test "blank and whitespace-only locations are unknown" {
    assert zip_prefix_of("") == "";
    assert zip_prefix_of("   ") == "";
}


test "a bare ZIP is never mistaken for a coordinate pair" {
    # "941, 10" parses as two floats but is out of latitude range for a real
    # reading and must fall through to digit parsing rather than resolving.
    assert parse_coords("941, 10") is None;
}


test "a null island reading is treated as a failed read" {
    assert parse_coords("0, 0") is None;
    assert zip_prefix_of("0, 0") == "";
}


test "malformed coordinate strings do not raise" {
    assert parse_coords("not, coords") is None;
    assert parse_coords("37.7749") is None;
    assert parse_coords("1, 2, 3") is None;
}


test "every service area centroid resolves back to its own prefix" {
    # Guards the table against a typo'd centroid that silently lands nearer some
    # other area than its own -- which would route a whole prefix's worth of
    # people to the wrong side of the bay.
    for (prefix, centroid) in AREA_CENTROIDS.items() {
        assert area_for_coords(centroid[0], centroid[1]) == prefix;
    }
}
