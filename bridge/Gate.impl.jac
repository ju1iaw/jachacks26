"""Handlers for the auth gate."""

impl Gate.do_login -> None {
    ok: bool = False;
    account: AccountView | None = None;
    busy = True;
    error = "";
    try {
        ok = await jacLogin(email, password);
    } except Exception {
        ok = False;
    }
    busy = False;
    if not ok {
        error = "That email and password didn't match an account.";
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
    auth_email = email.strip().lower();
    auth_password = password;
    busy = True;
    error = "";
    if not auth_email or "@" not in auth_email {
        busy = False;
        error = "Enter a valid email so you can sign back in.";
        stage = "account";
        return;
    }
    if len(auth_password) < 8 {
        busy = False;
        error = "Password needs at least 8 characters.";
        stage = "account";
        return;
    }
    try {
        signup_result = await jacSignup(auth_email, auth_password);
        if not signup_result["success"] {
            busy = False;
            # Already registered — try signing in with the same credentials.
            try {
                login_ok = await jacLogin(auth_email, auth_password);
            } except Exception {
                login_ok = False;
            }
            if not login_ok {
                error = "That email is already in use, or signup failed. Try signing in, or use a different email.";
                stage = "account";
                return;
            }
        } else {
            login_ok = await jacLogin(auth_email, auth_password);
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
        # Prefer the contact they gave; otherwise store the login email on the profile.
        method = contact_method if contact_value else "email";
        value = contact_value if contact_value else auth_email;
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
        stage = "account";
        error = "";
    }
}


impl Gate.next_account(e: MouseEvent) -> None {
    addr = email.strip().lower();
    if not addr or "@" not in addr {
        error = "Enter a valid email address.";
        return;
    }
    if len(password) < 8 {
        error = "Password needs at least 8 characters.";
        return;
    }
    email = addr;
    stage = "contact";
    # Prefill contact email from the login email they just chose.
    if not contact_value.strip() {
        contact_method = "email";
        contact_value = addr;
    }
    error = "";
}

impl Gate.next_contact(e: MouseEvent) -> None {
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

impl Gate.use_manual_location(e: MouseEvent) -> None {
    finish_signup();
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
