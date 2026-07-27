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
            storage = (window as any).localStorage;
            quick_access = storage.getItem("bridge_quick_access") != "off";
            locked = (
                quick_access
                and storage.getItem("bridge_screen_locked") == "true"
            );
        }
    } except Exception {
        role = "";
    }
    ready = True;
}


impl Shell.sign_out(e: MouseEvent) -> None {
    if role == "seeker" and quick_access {
        locked = True;
        seeker_panel = "home";
        (window as any).localStorage.setItem("bridge_screen_locked", "true");
        return;
    }
    sign_out_completely(e);
}


impl Shell.sign_out_completely(e: MouseEvent) -> None {
    jacLogout();
    (window as any).localStorage.removeItem("bridge_screen_locked");
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
    locked = False;
}


impl Shell.continue_quick_access(e: MouseEvent) -> None {
    (window as any).localStorage.removeItem("bridge_screen_locked");
    locked = False;
}


impl Shell.set_quick_access(enabled: bool) -> None {
    quick_access = enabled;
    storage = (window as any).localStorage;
    storage.setItem("bridge_quick_access", "on" if enabled else "off");
    if not enabled {
        storage.removeItem("bridge_screen_locked");
        locked = False;
    }
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
