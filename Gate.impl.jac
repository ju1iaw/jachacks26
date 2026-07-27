"""Handlers for the auth gate."""

impl Gate.submit_seeker_email -> None {
    clean = email.strip().lower();
    parts = clean.split("@");
    if (
        len(parts) != 2
        or not parts[0]
        or "." not in parts[1]
        or parts[1].startswith(".")
        or parts[1].endswith(".")
        or " " in clean
    ) {
        error = "Enter a valid email address.";
        return;
    }

    email = clean;
    busy = True;
    error = "";
    notice = "";
    passwordless_ok: bool = False;
    try {
        passwordless_ok = await jacLogin(
            {"type": "email", "value": clean},
            seeker_email_credential(clean)
        );
    } except Exception {
        passwordless_ok = False;
    }

    if passwordless_ok {
        account: AccountView | None = None;
        try {
            account = await me();
        } except Exception {
            account = None;
        }
        if account is not None and account.role == "seeker" {
            busy = False;
            onReady();
            return;
        }
        jacLogout();
        if account is not None and account.role == "helper" {
            busy = False;
            error = "That account belongs in the volunteer portal.";
            return;
        }
    }

    exists: bool = False;
    try {
        exists = await contact_registered("email", clean);
    } except Exception {
        busy = False;
        error = "We couldn’t check that email right now. Please try again.";
        return;
    }
    busy = False;
    if exists {
        login_stage = "password";
        password = "";
        return;
    }

    account_method = "email";
    contact_method = "email";
    contact_value = clean;
    display_name = "";
    password = seeker_email_credential(clean);
    mode = "signup";
    stage = "name";
    notice = "No account found — let’s create one.";
}


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
        phone_digits = digits_only(clean_login);
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
        phone_login = digits_only(email);
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
    if selected_role == "seeker" {
        try {
            _ = await set_password_enabled(True);
        } except Exception {
            # Login detection does not depend on this display-only preference.
            _ = None;
        }
    }
    onReady();
}


impl Gate.finish_signup -> None {
    signup_result: dict | None = None;
    login_ok: bool = False;
    clean_identity = email.strip();
    auth_type = "email" if account_method == "email" else "username";
    auth_value = (
        clean_identity.lower()
        if account_method == "email"
        else digits_only(clean_identity)
    );
    auth_identity = {"type": auth_type, "value": auth_value};
    auth_password = (
        seeker_email_credential(auth_value)
        if selected_role == "seeker"
        else password
    );
    busy = True;
    error = "";
    if account_method == "email" and (not auth_value or "@" not in auth_value) {
        busy = False;
        error = "Enter a valid email so you can sign back in.";
        stage = "account";
        return;
    }
    if account_method == "phone" and (len(auth_value) < 10 or len(auth_value) > 15) {
        busy = False;
        error = "Enter a valid phone number with 10 to 15 digits.";
        stage = "account";
        return;
    }
    if selected_role != "seeker" and len(auth_password) < 8 {
        busy = False;
        error = "Password needs at least 8 characters.";
        stage = "account";
        return;
    }
    try {
        signup_result = await jacSignup(auth_identity, auth_password);
        if not signup_result["success"] {
            busy = False;
            # Already registered — try signing in with the same credentials.
            try {
                login_ok = await jacLogin(auth_identity, auth_password);
            } except Exception {
                login_ok = False;
            }
            if not login_ok {
                error = (
                    "That phone number is already in use, or signup failed. Try signing in, or use a different number."
                    if account_method == "phone"
                    else "That email is already in use, or signup failed. Try signing in, or use a different email."
                );
                stage = "account";
                return;
            }
        } else {
            login_ok = await jacLogin(auth_identity, auth_password);
        }
    } except Exception {
        login_ok = False;
    }
    if not login_ok {
        busy = False;
        error = "Your account was created, but we couldn’t open it. Please try signing in.";
        stage = "account";
        return;
    }
    try {
        # Prefer their optional contact; otherwise use the sign-in identity.
        method = contact_method if contact_value else account_method;
        value = contact_value if contact_value else clean_identity;
        _ = await choose_role(selected_role, display_name, method, value, location);
        onReady();
    } except Exception as e {
        error = "Could not save that: " + str(e);
    }
    busy = False;
}


impl Gate.start_signup(e: MouseEvent) -> None {
    mode = "signup";
    stage = "name";
    login_stage = "email";
    notice = "";
    error = "";
}

impl Gate.choose_seeker(e: MouseEvent) -> None {
    selected_role = "seeker";
    mode = "login";
    stage = "creds";
    login_stage = "email";
    login_method = "email";
    account_method = "email";
    email = "";
    password = "";
    display_name = "";
    contact_method = "email";
    contact_value = "";
    notice = "";
    error = "";
}

impl Gate.choose_helper(e: MouseEvent) -> None {
    selected_role = "helper";
    mode = "login";
    stage = "creds";
    login_stage = "email";
    email = "";
    password = "";
    display_name = "";
    contact_value = "";
    notice = "";
    error = "";
}

impl Gate.back_to_directory(e: MouseEvent) -> None {
    mode = "directory";
    selected_role = "";
    notice = "";
    error = "";
}


impl Gate.to_signup(e: MouseEvent) -> None {
    mode = "signup";
    stage = "name";
    login_stage = "email";
    notice = "";
    error = "";
}

impl Gate.next_name(e: MouseEvent) -> None {
    if display_name.strip() {
        stage = "location" if selected_role == "seeker" else "account";
        if selected_role == "seeker" and not contact_value.strip() {
            contact_method = "email";
            contact_value = email;
        }
        error = "";
    }
}

impl Gate.next_account(e: MouseEvent) -> None {
    clean_identity = email.strip();
    if account_method == "email" {
        addr = clean_identity.lower();
        parts = addr.split("@");
        if len(parts) != 2 or not parts[0] or "." not in parts[1] or " " in addr {
            error = "Enter a valid email address.";
            return;
        }
        email = addr;
    } else {
        phone_digits = digits_only(clean_identity);
        if len(phone_digits) < 10 or len(phone_digits) > 15 {
            error = "Enter a valid phone number with 10 to 15 digits.";
            return;
        }
        email = phone_digits;
    }
    if len(password) < 8 {
        error = "Password needs at least 8 characters.";
        return;
    }
    stage = "contact";
    # Prefill contact information from the sign-in identity they just chose.
    if not contact_value.strip() {
        contact_method = account_method;
        contact_value = clean_identity;
    }
    error = "";
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
            phone_digits = digits_only(clean_contact);
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
    # Typed as any so client typecheck accepts the browser Geolocation API.
    geo = (navigator as any).geolocation;
    if geo is None {
        locating = False;
        error = "Location is not available in this browser. Enter it manually or skip.";
        return;
    }
    geo.getCurrentPosition(
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
    login_stage = "email";
    password = "";
    notice = "";
    error = "";
}
