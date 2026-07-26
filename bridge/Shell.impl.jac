"""Handlers for the shell."""

impl Shell.load -> None {
    if not jacIsLoggedIn() {
        signed_in = False;
        ready = True;
        return;
    }
    signed_in = True;
    try {
        account = await me();
        if account is not None {
            role = account.role;
            display_name = account.display_name;
            contact_method = account.contact_method;
            contact_value = account.contact_value;
            email = account.email;
            phone = account.phone;
            location = account.location;
            eligibility_notes = account.eligibility_notes;
        }
    } except Exception {
        role = "";
    }
    ready = True;
}


impl Shell.sign_out(e: MouseEvent) -> None {
    jacLogout();
    role = "";
    display_name = "";
    contact_method = "";
    contact_value = "";
    email = "";
    phone = "";
    location = "";
    eligibility_notes = "";
    signed_in = False;
    ready = True;
    seeker_panel = "home";
}


impl Shell.open_settings(e: MouseEvent) -> None {
    seeker_panel = "home" if seeker_panel == "settings" else "settings";
}


impl Shell.open_past(e: MouseEvent) -> None {
    seeker_panel = "home" if seeker_panel == "past" else "past";
}


impl Shell.go_home -> None {
    seeker_panel = "home";
}
