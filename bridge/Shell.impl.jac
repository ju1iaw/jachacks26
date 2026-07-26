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
    signed_in = False;
    ready = True;
}
