"""Handlers for the auth gate."""

impl Gate.do_login -> None {
    ok: bool = False;
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
    onReady();
}


impl Gate.do_signup -> None {
    signup_result: dict | None = None;
    login_ok: bool = False;

    if not email.strip() or len(password) < 8 {
        error = "Email plus a password of at least 8 characters, please.";
        return;
    }
    busy = True;
    error = "";
    try {
        signup_result = await jacSignup(email, password);
        if not signup_result["success"] {
            busy = False;
            error = "That email is already registered - try signing in.";
            return;
        }
        login_ok = await jacLogin(email, password);
    } except Exception {
        login_ok = False;
    }
    busy = False;
    if not login_ok {
        error = "Account created, but signing in failed. Try the sign-in tab.";
        return;
    }
    stage = "role";
}


impl Gate.pick_seeker -> None {
    busy = True;
    try {
        _ = await choose_role("seeker", display_name if display_name else "friend");
        onReady();
    } except Exception as e {
        error = "Could not save that: " + str(e);
    }
    busy = False;
}


impl Gate.pick_helper -> None {
    busy = True;
    try {
        _ = await choose_role("helper", display_name if display_name else "volunteer");
        onReady();
    } except Exception as e {
        error = "Could not save that: " + str(e);
    }
    busy = False;
}


impl Gate.to_login(e: MouseEvent) -> None {
    mode = "login";
    error = "";
}


impl Gate.to_signup(e: MouseEvent) -> None {
    mode = "signup";
    error = "";
}


impl Gate.fill_seeker(e: MouseEvent) -> None {
    mode = "login";
    email = "maria@bridge.demo";
    password = "bridge1234";
    error = "";
}


impl Gate.fill_helper(e: MouseEvent) -> None {
    mode = "login";
    email = "sam@bridge.demo";
    password = "bridge1234";
    error = "";
}
