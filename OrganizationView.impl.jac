"""Handlers for the organization console."""

impl OrganizationView.refresh -> None {
    try {
        result = await root spawn OrganizationBoard();
        if result.reports and len(result.reports) > 0 {
            board = result.reports[0];
            org_name = board.org_name;
            tallies = board.tallies;
            pending = board.pending_offers;
            claims = board.matched_needs;
            if tallies and occupancy == "0" {
                occupancy = str(tallies[0].current_people);
            }
        }
    } except Exception as e {
        error = "Could not load the organization ledger: " + str(e);
    }
}


impl OrganizationView.confirm_receipt(pledge_id: str, units: int) -> None {
    busy = True;
    error = "";
    try {
        _ = await root spawn OrganizationReceiptWalker(
            pledge_id=pledge_id,
            units=units
        );
        await refresh();
    } except Exception as e {
        error = "Receipt was not recorded: " + str(e);
    }
    busy = False;
}


impl OrganizationView.confirm_distribution(code: str, people: int) -> None {
    busy = True;
    error = "";
    try {
        _ = await root spawn OrganizationDistributionWalker(
            need_code=code,
            people_served=people
        );
        await refresh();
    } except Exception as e {
        error = "Distribution was not recorded: " + str(e);
    }
    busy = False;
}


impl OrganizationView.save_occupancy -> None {
    busy = True;
    error = "";
    try {
        value = int(occupancy) if occupancy else 0;
        _ = await root spawn OrganizationOccupancyWalker(current_people=value);
        await refresh();
    } except Exception as e {
        error = "Occupancy was not recorded: " + str(e);
    }
    busy = False;
}
