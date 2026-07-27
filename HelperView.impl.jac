"""Handlers for HelperView."""

def _ref_offers(ref: Ref[list[OfferView]]) -> list[OfferView] {
    cur = ref.current;
    return cur if cur else [];
}


def _ref_ids(ref: Ref[list[str]]) -> list[str] {
    cur = ref.current;
    return cur if cur else [];
}


impl HelperView.refresh -> None {
    try {
        result = await root spawn CommunityBoard();
        if result.reports and len(result.reports) > 0 {
            view = result.reports[0];
            needs = view.needs;
            orgs = view.orgs;
            opportunities = view.opportunities;

            # Seed active offers from this helper's live pledges (once per id).
            known = _ref_ids(known_ref);
            next_offers = _ref_offers(offers_ref);
            for p in view.pledges {
                if not p.mine or p.status == "withdrawn" {
                    continue;
                }
                ov = offer_from_pledge(p);
                if ov.id in known or ov.pledge_id in known {
                    continue;
                }
                next_offers = next_offers + [ov];
                known = known + [ov.id, ov.pledge_id];
            }
            offers_ref.current = next_offers;
            known_ref.current = known;
            offers = next_offers;
            past_offers = _ref_offers(past_ref);
        }
    } except Exception {
        chat_reply = chat_reply;
    }
}


impl HelperView.submit_offer -> None {
    if not offer_text.strip() {
        error = "Tell Bridge how you can help first.";
        return;
    }
    busy = True;
    error = "";
    chat_reply = "";
    text = offer_text.strip();
    try {
        result = await root spawn HelperOfferWalker(text=text);
        chat_reply = result.reply if result.reply else "Added to your offered services.";
        known = _ref_ids(known_ref);
        next_offers = _ref_offers(offers_ref);
        added = 0;
        if result.reports {
            for ov in result.reports {
                if ov.id in known {
                    continue;
                }
                next_offers = next_offers + [ov];
                known = known + [ov.id];
                if ov.pledge_id {
                    known = known + [ov.pledge_id];
                }
                added = added + 1;
            }
        }
        if added == 0 {
            for d in demo_helper_offers() {
                if d.id not in known {
                    next_offers = next_offers + [d];
                    known = known + [d.id];
                    added = added + 1;
                }
            }
            if not chat_reply {
                chat_reply = "Here is an example offer based on what you described.";
            }
        }
        offers_ref.current = next_offers;
        known_ref.current = known;
        offers = next_offers;
        offer_text = "";
        await refresh();
    } except Exception as e {
        raw = str(e);
        if "ENGINE_UNAVAILABLE" in raw {
            error = "No model connection — showing an example offer you can edit.";
        } else {
            error = "Something went wrong — showing an example offer.";
        }
        known = _ref_ids(known_ref);
        next_offers = _ref_offers(offers_ref);
        for d in demo_helper_offers() {
            if d.id not in known {
                next_offers = next_offers + [d];
                known = known + [d.id];
            }
        }
        offers_ref.current = next_offers;
        known_ref.current = known;
        offers = next_offers;
        chat_reply = "Example offer added on the right — expand it for details.";
    }
    busy = False;
}


impl HelperView.remove_offer(oid: str) -> None {
    cur = _ref_offers(offers_ref);
    moved = [o for o in cur if o.id == oid];
    next_offers = [o for o in cur if o.id != oid];
    offers_ref.current = next_offers;
    offers = next_offers;
    if len(moved) == 0 {
        return;
    }
    next_past = _ref_offers(past_ref) + moved;
    past_ref.current = next_past;
    past_offers = next_past;
    pid = moved[0].pledge_id;
    if pid {
        try {
            _ = await root spawn RetirePledgeWalker(pledge_id=pid);
        } except Exception {
            pid = pid;
        }
    }
}


impl HelperView.toggle_past -> None {
    show_past = not show_past;
}
