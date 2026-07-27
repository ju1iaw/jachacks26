"""Bridge - sign in / sign up, and the one question that splits the app in two.

Which side of Bridge you are on is not a UI toggle: it writes an `Account` node
onto your own root, and from then on every walker you spawn runs against your
graph, not anyone else's.
"""

import from "@jac/runtime" { jacLogin, jacLogout, jacSignup }
import from react { useEffect, useRef }
import from .components.Auth { digits_only, seeker_email_credential }
import from .components.Bits { Brand }

sv import from .core.commons {
    choose_role, contact_registered, me, set_password_enabled, suggest_addresses
}
sv import from .core.graph { AccountView }


def:pub Gate(onReady: Callable[[], None]) -> JsxElement {
    has mode: str = "directory";
    has selected_role: str = "";
    has login_method: str = "email";
    has account_method: str = "email";
    has email: str = "";
    has password: str = "";
    has login_stage: str = "email";
    has display_name: str = "";
    has stage: str = "creds";
    has contact_method: str = "email";
    has contact_value: str = "";
    has location: str = "";
    has locating: bool = False;
    has address_valid: bool = False;
    has address_error: str = "";
    has map_url: str = "";
    has address_suggestions: list[dict[str, str]] = [];
    has searching_address: bool = False;
    has busy: bool = False;
    has error: str = "";
    has notice: str = "";
    search_sequence: any = useRef(0);

    async def do_login -> None;
    async def submit_seeker_email -> None;
    async def finish_signup -> None;
    def start_signup(e: MouseEvent) -> None;
    def choose_seeker(e: MouseEvent) -> None;
    def choose_helper(e: MouseEvent) -> None;
    def back_to_directory(e: MouseEvent) -> None;
    def next_name(e: MouseEvent) -> None;
    def next_account(e: MouseEvent) -> None;
    async def next_contact -> None;
    def skip_contact(e: MouseEvent) -> None;
    def request_location(e: MouseEvent) -> None;
    async def load_address_suggestions -> None;
    def select_address(suggestion: dict[str, str]) -> None;
    def use_manual_location(e: MouseEvent) -> None;
    def skip_location(e: MouseEvent) -> None;
    def back_to_login(e: MouseEvent) -> None;
    def to_signup(e: MouseEvent) -> None;

    useEffect(lambda {
        if stage != "location" or address_valid or len(location.strip()) < 4 {
            address_suggestions = [];
            return;
        }
        timer = setTimeout(lambda { load_address_suggestions(); }, 300);
        return lambda { clearTimeout(timer); };
    }, [location, stage, address_valid]);

    if mode == "directory" {
        return <div className="directory-page">
            <section className="directory-hero">
                <img className="directory-logo" src="/assets/bridge-logo.png" alt="Bridge logo"/>
                <div className="directory-name brand-name">Bridge</div>
                <p className="directory-tagline">Nobody has to ask for help alone.</p>
                <div className="directory-actions">
                    <button className="directory-choice volunteer" onClick={choose_helper}>
                        <span className="choice-kicker">Share what you can</span>
                        <b>I’m a volunteer</b>
                        <span>Offer time, goods, or support through a trusted local organization.</span>
                    </button>
                    <button className="directory-choice seeker" onClick={choose_seeker}>
                        <span className="choice-kicker">Find your next step</span>
                        <b>I need help right now</b>
                        <span>Tell Bridge what is happening and get a private, practical plan.</span>
                    </button>
                </div>
                <a className="about-link" href="#about-bridge">About Bridge <span>↓</span></a>
            </section>
            <section className="about" id="about-bridge">
                <div className="about-head">
                    <div className="eyebrow">About Bridge</div>
                    <h2>Help should be easier to reach.</h2>
                    <p className="about-lead">
                        Bridge privately connects people with nearby organizations and
                        community support, turning a difficult moment into a clear next step.
                    </p>
                </div>

                <div className="about-grid">
                    <article className="about-card">
                        <span className="about-mark">01</span>
                        <h3>Volunteers never see who you are</h3>
                        <p>
                            They see one line: what is needed, household size, and a
                            three-digit ZIP area. No name, no address, no contact details.
                            A second AI pass audits that summary for anything identifying
                            before it is published — and Bridge will never ask where you live.
                        </p>
                    </article>
                    <article className="about-card">
                        <span className="about-mark">02</span>
                        <h3>The match finds itself</h3>
                        <p>
                            Volunteers offer what they have through a local organization.
                            People describe what they need. When the two genuinely fit,
                            Bridge connects them — nobody presses a button, and the two
                            sides never contact each other directly.
                        </p>
                    </article>
                    <article className="about-card">
                        <span className="about-mark">03</span>
                        <h3>You learn what is blocking you first</h3>
                        <p>
                            Bridge looks up what each organization actually requires at the
                            door, then puts the step that unblocks you in front of it —
                            “ask the front desk for a signed letter”, not “proof of address
                            required”.
                        </p>
                    </article>
                </div>

                <div className="about-proof">
                    <div className="about-proof-copy">
                        <div className="eyebrow">What a volunteer sees</div>
                        <p>
                            This is the whole record someone offering help works from.
                            Everything else stays with you.
                        </p>
                        <p className="about-proof-note">
                            Fit means usable, not just the same category — a pledge of dry
                            rice and beans is never offered to a household with no stove.
                        </p>
                    </div>
                    <div className="about-proof-card" aria-hidden="true">
                        <div className="about-proof-top">
                            <span className="about-proof-tag">food</span>
                            <span className="about-proof-code">N-7291</span>
                        </div>
                        <p className="about-proof-line">
                            Needs groceries. Household of 3; no car, no stove access.
                        </p>
                        <div className="about-proof-chips">
                            <span>no name</span>
                            <span>no address</span>
                            <span>ZIP area only</span>
                        </div>
                    </div>
                </div>

                <ul className="about-facts">
                    <li>Free to use</li>
                    <li>People seeking help can start with just an email</li>
                    <li>Nothing you write is shared without being anonymized first</li>
                </ul>
            </section>
        </div>;
    }

    return <div className="gate">
        <div style={{"marginBottom": "18px", "justifyContent": "center", "display": "flex"}}>
            <Brand tagline={"bridge for volunteers" if selected_role == "helper" else ""}/>
        </div>

        <div className="card">
            {if mode == "signup" {
                <div className="signup-flow" key="signup">
                    {if stage != "name" {
                        <button className="back-link" onClick={back_to_login} disabled={busy}>
                            ← back to sign in
                        </button>
                    }}

                    <div className="progress" aria-label="Signup progress">
                        <span className={"active" if stage == "name" else "done"}></span>
                        {if selected_role == "helper" {
                            <span
                                key="account-progress"
                                className={"active" if stage == "account" else ("done" if stage in ["contact", "location"] else "")}
                            ></span>
                        }}
                        {if selected_role == "helper" {
                            <span
                                key="contact-progress"
                                className={"active" if stage == "contact" else ("done" if stage == "location" else "")}
                            ></span>
                        }}
                        <span className={"active" if stage == "location" else ""}></span>
                    </div>

                    {if stage == "name" {
                        <div key="name">
                            {if notice {
                                <p className="auth-notice" key="no-account">{notice}</p>
                            }}
                            <div className="eyebrow">Let’s get acquainted</div>
                            <h1>What’s your name?</h1>
                            <input
                                className="field hero-field"
                                value={display_name}
                                placeholder="Enter your name"
                                autofocus={True}
                                onChange={lambda (e: ChangeEvent) { display_name = e.target.value; }}
                            />
                            <button className="btn primary full" onClick={next_name} disabled={not display_name.strip()}>
                                Continue
                            </button>
                            <button className="text-btn account-exists" onClick={back_to_login}>
                                I already have an account
                            </button>
                        </div>
                    }}

                    {if stage == "account" {
                        <div key="account">
                            <div className="eyebrow">Save your account</div>
                            <h1>Choose how you’ll sign in</h1>
                            <p className="muted small" style={{"marginBottom": "14px"}}>
                                Use an email address or phone number with a password.
                            </p>
                            <div className="contact-tabs" role="tablist" aria-label="Signup method">
                                <button
                                    role="tab"
                                    aria-selected={account_method == "email"}
                                    className={"contact-tab active" if account_method == "email" else "contact-tab"}
                                    onClick={lambda {
                                        account_method = "email";
                                        email = "";
                                        error = "";
                                    }}
                                >Email</button>
                                <button
                                    role="tab"
                                    aria-selected={account_method == "phone"}
                                    className={"contact-tab active" if account_method == "phone" else "contact-tab"}
                                    onClick={lambda {
                                        account_method = "phone";
                                        email = "";
                                        error = "";
                                    }}
                                >Phone</button>
                            </div>
                            <label className="lbl">
                                {"Email" if account_method == "email" else "Phone number"}
                            </label>
                            <input
                                className="field hero-field"
                                type={"email" if account_method == "email" else "tel"}
                                value={email}
                                autocomplete={"email" if account_method == "email" else "tel"}
                                maxlength={"254" if account_method == "email" else "25"}
                                placeholder={"you@example.com" if account_method == "email" else "(555) 123-4567"}
                                autofocus={True}
                                onChange={lambda (e: ChangeEvent) {
                                    email = e.target.value;
                                    error = "";
                                }}
                            />
                            <label className="lbl" style={{"marginTop": "12px"}}>Password</label>
                            <input
                                className="field hero-field"
                                type="password"
                                value={password}
                                placeholder="At least 8 characters"
                                onChange={lambda (e: ChangeEvent) { password = e.target.value; }}
                            />
                            <button className="btn primary full" onClick={next_account} disabled={busy}>
                                Continue
                            </button>
                        </div>
                    }}

                    {if stage == "contact" {
                        <div key="contact">
                            <div className="eyebrow">Stay in touch</div>
                            <h1>What’s the best way to contact you?</h1>
                            <div className="contact-tabs" role="tablist" aria-label="Contact method">
                                <button
                                    role="tab"
                                    aria-selected={contact_method == "email"}
                                    className={"contact-tab active" if contact_method == "email" else "contact-tab"}
                                    onClick={lambda { contact_method = "email"; contact_value = ""; }}
                                >Email</button>
                                <button
                                    role="tab"
                                    aria-selected={contact_method == "phone"}
                                    className={"contact-tab active" if contact_method == "phone" else "contact-tab"}
                                    onClick={lambda { contact_method = "phone"; contact_value = ""; }}
                                >Phone</button>
                            </div>
                            <input
                                className="field hero-field"
                                type={"email" if contact_method == "email" else "tel"}
                                value={contact_value}
                                autocomplete={"email" if contact_method == "email" else "tel"}
                                maxlength={"254" if contact_method == "email" else "25"}
                                placeholder={"you@example.com" if contact_method == "email" else "(555) 123-4567"}
                                onChange={lambda (e: ChangeEvent) {
                                    contact_value = e.target.value;
                                    error = "";
                                }}
                            />
                            <button className="btn primary full" onClick={next_contact} disabled={busy}>
                                {"Checking…" if busy else ("Continue" if contact_value.strip() else "Skip for now")}
                            </button>
                        </div>
                    }}

                    {if stage == "location" {
                        <div key="location">
                            <div className="eyebrow">Find nearby support</div>
                            <h1>Where are you located?</h1>
                            <p className="muted small">Share your location or enter a city, neighborhood, or ZIP.</p>
                            <button className="location-opt" onClick={request_location} disabled={locating or busy}>
                                <span className="location-icon">◎</span>
                                <span>
                                    <b>{"Finding your location…" if locating else "Use my current location"}</b>
                                    <span className="small muted">Your browser will ask for permission.</span>
                                </span>
                            </button>
                            <div className="or"><span>or enter it manually</span></div>
                            <input
                                className="field hero-field"
                                value={location}
                                placeholder="Search for an address or place"
                                autocomplete="off"
                                onChange={lambda (e: ChangeEvent) {
                                    search_sequence.current += 1;
                                    location = e.target.value;
                                    address_valid = False;
                                    address_error = "";
                                    map_url = "";
                                    searching_address = False;
                                }}
                            />

                            {if searching_address {
                                <div className="suggestion-status" key="searching">Searching places…</div>
                            }}

                            {if len(address_suggestions) > 0 and not address_valid {
                                <div className="address-suggestions" key="suggestions" role="listbox">
                                    {for (i, suggestion) in enumerate(address_suggestions) {
                                        <button
                                            className="address-suggestion"
                                            key={str(i)}
                                            role="option"
                                            onClick={lambda { select_address(suggestion); }}
                                        >
                                            <span className="suggestion-pin">●</span>
                                            <span>{suggestion["label"]}</span>
                                        </button>
                                    }}
                                </div>
                            }}

                            {if address_error {
                                <p className="address-error" key="address-error">{address_error}</p>
                            }}

                            {if map_url {
                                <div className="map-card" key="map">
                                    <iframe
                                        className="address-map"
                                        src={map_url}
                                        title={"Selected address map" if address_valid else "Best address match map preview"}
                                        loading="lazy"
                                    ></iframe>
                                    <div className="map-confirmed">
                                        <span className="map-pin">●</span>
                                        <span>
                                            <b>{"Location selected" if address_valid else "Best match preview"}</b>
                                            <small>
                                                {location if address_valid else "Choose a suggestion above to confirm this pin."}
                                            </small>
                                        </span>
                                    </div>
                                    <a
                                        className="map-attribution"
                                        href="https://www.openstreetmap.org/copyright"
                                        target="_blank"
                                    >© OpenStreetMap contributors</a>
                                </div>
                            }}

                            {if address_valid {
                                <button className="btn primary full" key="continue" onClick={use_manual_location} disabled={busy}>
                                    Continue
                                </button>
                            } else {
                                <button
                                    className="btn ghost full"
                                    key="skip"
                                    onClick={skip_location}
                                    disabled={busy}
                                >
                                    {"Skip for now" if not location.strip() else "Skip address for now"}
                                </button>
                            }}
                        </div>
                    }}

                    {if error {
                        <p className="err" key="signup-error" style={{"marginTop": "12px"}}>{error}</p>
                    }}
                </div>
            } else {
                <div className="login-flow" key="login">
                    <button className="back-link" onClick={back_to_directory}>
                        ← choose a different path
                    </button>
                    {if selected_role == "seeker" {
                        <div key="seeker-login">
                            <div className="eyebrow">Private support</div>
                            <h1>{"Enter your password" if login_stage == "password" else "What’s your email?"}</h1>
                            {if login_stage == "email" {
                                <div key="seeker-email">
                                    <p className="muted small" style={{"marginTop": "8px"}}>
                                        No password is required unless you chose one in Settings.
                                    </p>
                                    <label className="lbl" style={{"marginTop": "18px"}}>Email</label>
                                    <input
                                        className="field"
                                        type="email"
                                        value={email}
                                        autocomplete="email"
                                        maxlength="254"
                                        placeholder="you@example.com"
                                        autofocus={True}
                                        onChange={lambda (e: ChangeEvent) {
                                            email = e.target.value;
                                            error = "";
                                        }}
                                    />
                                    <button
                                        className="btn primary full"
                                        onClick={submit_seeker_email}
                                        disabled={busy or not email.strip()}
                                    >
                                        {"Checking…" if busy else "Continue"}
                                    </button>
                                </div>
                            } else {
                                <div key="seeker-password">
                                    <p className="muted small" style={{"marginTop": "8px"}}>
                                        A password is configured for <b>{email}</b>.
                                    </p>
                                    <label className="lbl" style={{"marginTop": "18px"}}>Password</label>
                                    <input
                                        className="field"
                                        type="password"
                                        value={password}
                                        autocomplete="current-password"
                                        autofocus={True}
                                        onChange={lambda (e: ChangeEvent) {
                                            password = e.target.value;
                                            error = "";
                                        }}
                                    />
                                    <button
                                        className="btn primary full"
                                        onClick={do_login}
                                        disabled={busy or not password}
                                    >
                                        {"Working…" if busy else "Sign in"}
                                    </button>
                                    <button
                                        className="text-btn"
                                        onClick={lambda {
                                            login_stage = "email";
                                            password = "";
                                            error = "";
                                        }}
                                    >
                                        Use a different email
                                    </button>
                                </div>
                            }}
                        </div>
                    } else {
                        <div key="helper-login">
                            <div className="eyebrow">Volunteer portal</div>
                            <h1>Sign in to help</h1>
                            <div className="contact-tabs login-tabs" role="tablist" aria-label="Sign-in method">
                                <button
                                    role="tab"
                                    aria-selected={login_method == "email"}
                                    className={"contact-tab active" if login_method == "email" else "contact-tab"}
                                    onClick={lambda { login_method = "email"; email = ""; error = ""; }}
                                >Email</button>
                                <button
                                    role="tab"
                                    aria-selected={login_method == "phone"}
                                    className={"contact-tab active" if login_method == "phone" else "contact-tab"}
                                    onClick={lambda { login_method = "phone"; email = ""; error = ""; }}
                                >Phone</button>
                            </div>
                            <label className="lbl" style={{"marginTop": "12px"}}>
                                {"Email" if login_method == "email" else "Phone number"}
                            </label>
                            <input
                                className="field"
                                type={"email" if login_method == "email" else "tel"}
                                value={email}
                                autocomplete={"email" if login_method == "email" else "tel"}
                                maxlength={"254" if login_method == "email" else "25"}
                                placeholder={"you@example.com" if login_method == "email" else "(555) 123-4567"}
                                onChange={lambda (e: ChangeEvent) {
                                    email = e.target.value;
                                    error = "";
                                }}
                            />
                            <label className="lbl" style={{"marginTop": "12px"}}>Password</label>
                            <input
                                className="field"
                                type="password"
                                value={password}
                                autocomplete="current-password"
                                onChange={lambda (e: ChangeEvent) { password = e.target.value; }}
                            />
                            <button
                                className="btn primary full"
                                onClick={do_login}
                                disabled={busy}
                            >
                                {"Working…" if busy else "Sign in"}
                            </button>
                            <button className="btn ghost full create-account" onClick={start_signup}>
                                Create new account
                            </button>
                        </div>
                    }}

                    {if error {
                        <p className="err" key="e2" style={{"marginTop": "10px"}}>{error}</p>
                    }}

                </div>
            }}
        </div>
    </div>;
}
