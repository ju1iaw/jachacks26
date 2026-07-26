"""Handlers for the auth gate."""

impl Gate.do_login -> None {
    ok: bool = False;
    account: AccountView | None = None;
    clean_login = email.strip();
    if login_method == "email" {
        email_parts = clean_login.split("@");
        if (
            len(email_parts) != 2
            or not email_parts[0]
            or "." not in email_parts[1]
            or email_parts[1].startswith(".")
            or email_parts[1].endswith(".")
            or " " in clean_login
        ) {
            error = "Enter a valid email address.";
            return;
        }
    } else {
        phone_digits = "".join([char for char in clean_login if char.isdigit()]);
        if len(phone_digits) < 10 or len(phone_digits) > 15 {
            error = "Enter a valid phone number with 10 to 15 digits.";
            return;
        }
    }
    busy = True;
    error = "";
    try {
        # Jac supports email and username identities. Phone accounts use their
        # normalized phone number as the username identity.
        identity_type = "email" if login_method == "email" else "username";
        phone_login = "".join([char for char in email if char.isdigit()]);
        identity_value = email.strip().lower() if login_method == "email" else phone_login;
        ok = await jacLogin({"type": identity_type, "value": identity_value}, password);
    } except Exception {
        ok = False;
    }
    busy = False;
    if not ok {
        error = (
            "That phone number and password didn't match an account."
            if login_method == "phone"
            else "That email and password didn't match an account."
        );
        return;
    }
    try {
        account = await me();
    } except Exception {
        account = None;
    }
    if account is None or account.role != selected_role {
        jacLogout();
        error = (
            "That account belongs in the volunteer portal."
            if account is not None and account.role == "helper"
            else "That account belongs in the support portal."
        );
        return;
    }
    onReady();
}


impl Gate.finish_signup -> None {
    signup_result: dict | None = None;
    login_ok: bool = False;
    stamp = str(Date.now());
    auth_email = "bridge-" + stamp + "@session.local";
    auth_password = "Bridge-" + stamp;
    busy = True;
    error = "";
    try {
        signup_result = await jacSignup(auth_email, auth_password);
        if not signup_result["success"] {
            busy = False;
            error = "We couldn’t create your account. Please try again.";
            return;
        }
        login_ok = await jacLogin(auth_email, auth_password);
    } except Exception {
        login_ok = False;
    }
    if not login_ok {
        busy = False;
        error = "Your account was created, but we couldn’t open it. Please try again.";
        return;
    }
    try {
        _ = await choose_role(selected_role, display_name, contact_method if contact_value else "", contact_value, location);
        onReady();
    } except Exception as e {
        error = "Could not save that: " + str(e);
    }
    busy = False;
}


impl Gate.start_signup(e: MouseEvent) -> None {
    mode = "signup";
    stage = "name";
    error = "";
}

impl Gate.choose_seeker(e: MouseEvent) -> None {
    selected_role = "seeker";
    mode = "login";
    stage = "creds";
    error = "";
}

impl Gate.choose_helper(e: MouseEvent) -> None {
    selected_role = "helper";
    mode = "login";
    stage = "creds";
    error = "";
}

impl Gate.back_to_directory(e: MouseEvent) -> None {
    mode = "directory";
    selected_role = "";
    error = "";
}


impl Gate.to_signup(e: MouseEvent) -> None {
    mode = "signup";
    stage = "name";
    error = "";
}

impl Gate.next_name(e: MouseEvent) -> None {
    if display_name.strip() {
        stage = "contact";
        error = "";
    }
}

impl Gate.next_contact -> None {
    if contact_value.strip() {
        clean_contact = contact_value.strip();
        if contact_method == "email" {
            email_parts = clean_contact.split("@");
            if (
                len(email_parts) != 2
                or not email_parts[0]
                or "." not in email_parts[1]
                or email_parts[1].startswith(".")
                or email_parts[1].endswith(".")
                or " " in clean_contact
            ) {
                error = "Enter a valid email address, or skip for now.";
                return;
            }
        } else {
            phone_digits = "".join([char for char in clean_contact if char.isdigit()]);
            if len(phone_digits) < 10 or len(phone_digits) > 15 {
                error = "Enter a valid phone number with 10 to 15 digits, or skip for now.";
                return;
            }
        }
        busy = True;
        exists: bool = False;
        try {
            exists = await contact_registered(contact_method, contact_value);
        } except Exception {
            busy = False;
            error = "We couldn’t check that contact right now. Please try again.";
            return;
        }
        busy = False;
        if exists {
            login_method = contact_method;
            email = contact_value;
            mode = "login";
            stage = "creds";
            error = "You already have an account. Sign in below.";
            return;
        }
    }
    stage = "location";
    error = "";
}

impl Gate.skip_contact(e: MouseEvent) -> None {
    contact_value = "";
    stage = "location";
}

impl Gate.request_location(e: MouseEvent) -> None {
    locating = True;
    error = "";
    navigator.geolocation.getCurrentPosition(
        lambda (position: any) {
            location = str(position.coords.latitude) + ", " + str(position.coords.longitude);
            locating = False;
            finish_signup();
        },
        lambda (failure: any) {
            locating = False;
            error = "Location access was denied. Enter it manually or skip for now.";
        }
    );
}

impl Gate.load_address_suggestions -> None {
    if len(location.strip()) < 4 or address_valid {
        return;
    }
    query = location.strip();
    search_sequence.current += 1;
    request_id = search_sequence.current;
    searching_address = True;
    address_error = "";
    try {
        results = await suggest_addresses(query);
        if request_id != search_sequence.current {
            return;
        }
        address_suggestions = results;
        if len(results) > 0 {
            address_error = "";
            map_url = results[0]["map_url"];
        } else {
            map_url = "";
            address_error = "No matching places found. Try adding a city, state, or ZIP.";
        }
    } except Exception {
        if request_id != search_sequence.current {
            return;
        }
        address_suggestions = [];
        map_url = "";
        address_error = "Place search is unavailable right now. Try again in a moment.";
    }
    if request_id == search_sequence.current {
        searching_address = False;
    }
}

impl Gate.select_address(suggestion: dict[str, str]) -> None {
    search_sequence.current += 1;
    location = suggestion["label"];
    map_url = suggestion["map_url"];
    address_valid = True;
    address_error = "";
    address_suggestions = [];
}

impl Gate.use_manual_location(e: MouseEvent) -> None {
    if address_valid {
        finish_signup();
    }
}

impl Gate.skip_location(e: MouseEvent) -> None {
    location = "";
    finish_signup();
}

impl Gate.back_to_login(e: MouseEvent) -> None {
    mode = "login";
    stage = "creds";
    error = "";
}
