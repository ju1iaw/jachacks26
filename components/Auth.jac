"""Client-safe authentication helpers.

People seeking help may deliberately use email-only access. Jac still requires
a credential internally, so these accounts use a stable machine credential
derived from the normalized email. This is not intended to add security: the
email itself is the access factor until the person chooses a password in
Settings.
"""


def seeker_email_credential(email: str) -> str {
    return "bridge::seeker::email-only::" + email.strip().lower();
}


def digits_only(value: str) -> str {
    return "".join([
        char for char in value.split("")
        if char >= "0" and char <= "9"
    ]);
}
