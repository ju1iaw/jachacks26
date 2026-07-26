"""Bridge - sign in / sign up, and the one question that splits the app in two.

Which side of Bridge you are on is not a UI toggle: it writes an `Account` node
onto your own root, and from then on every walker you spawn runs against your
graph, not anyone else's.
"""

import from "@jac/runtime" { jacLogin, jacLogout, jacSignup }
import from .components.Bits { Brand }

sv import from .core.commons { choose_role, me }
sv import from .core.graph { AccountView }


def:pub Gate(onReady: Callable[[], None]) -> JsxElement {
    has mode: str = "directory";
    has selected_role: str = "";
    has email: str = "";
    has password: str = "";
    has display_name: str = "";
    has stage: str = "creds";
    has contact_method: str = "email";
    has contact_value: str = "";
    has location: str = "";
    has locating: bool = False;
    has busy: bool = False;
    has error: str = "";

    async def do_login -> None;
    async def finish_signup -> None;
    def start_signup(e: MouseEvent) -> None;
    def choose_seeker(e: MouseEvent) -> None;
    def choose_helper(e: MouseEvent) -> None;
    def back_to_directory(e: MouseEvent) -> None;
    def next_name(e: MouseEvent) -> None;
    def next_contact(e: MouseEvent) -> None;
    def skip_contact(e: MouseEvent) -> None;
    def request_location(e: MouseEvent) -> None;
    def use_manual_location(e: MouseEvent) -> None;
    def skip_location(e: MouseEvent) -> None;
    def back_to_login(e: MouseEvent) -> None;
    def to_signup(e: MouseEvent) -> None;

    if mode == "directory" {
        return <div className="directory-page">
            <section className="directory-hero">
                <img className="directory-logo" src="/assets/bridge-logo.png" alt="Bridge logo"/>
                <div className="directory-name">Bridge</div>
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
            <section className="about-placeholder" id="about-bridge">
                <div className="eyebrow">About Bridge</div>
                <h2>Help should be easier to reach.</h2>
                <p>
                    Bridge privately connects people with nearby organizations and
                    community support, turning a difficult moment into a clear next step.
                </p>
            </section>
        </div>;
    }

    return <div className="gate">
        <div style={{"marginBottom": "18px", "justifyContent": "center", "display": "flex"}}>
            <Brand tagline={"volunteer access" if selected_role == "helper" else "support access"}/>
        </div>

        <div className="card">
            {if mode == "signup" {
                <div className="signup-flow" key="signup">
                    <button className="back-link" onClick={back_to_login} disabled={busy}>
                        ← back to sign in
                    </button>

                    <div className="progress" aria-label="Signup progress">
                        <span className={"active" if stage == "name" else "done"}></span>
                        <span className={"active" if stage == "contact" else ("done" if stage == "location" else "")}></span>
                        <span className={"active" if stage == "location" else ""}></span>
                    </div>

                    {if stage == "name" {
                        <div key="name">
                            <div className="eyebrow">Let’s get acquainted</div>
                            <h1>What’s your name?</h1>
                            <input
                                className="field hero-field"
                                value={display_name}
                                placeholder="First name is plenty"
                                autofocus={True}
                                onChange={lambda (e: ChangeEvent) { display_name = e.target.value; }}
                            />
                            <button className="btn primary full" onClick={next_name} disabled={not display_name.strip()}>
                                Continue
                            </button>
                        </div>
                    }}

                    {if stage == "contact" {
                        <div key="contact">
                            <div className="eyebrow">Stay in touch</div>
                            <h1>What’s the best way to contact you?</h1>
                            <p className="muted small">This is optional. We’ll only use it for updates you ask for.</p>
                            <div className="choice-row">
                                <button className={"choice active" if contact_method == "email" else "choice"} onClick={lambda { contact_method = "email"; contact_value = ""; }}>Email</button>
                                <button className={"choice active" if contact_method == "phone" else "choice"} onClick={lambda { contact_method = "phone"; contact_value = ""; }}>Phone</button>
                            </div>
                            <input
                                className="field hero-field"
                                type={"email" if contact_method == "email" else "tel"}
                                value={contact_value}
                                placeholder={"you@example.com" if contact_method == "email" else "(555) 123-4567"}
                                onChange={lambda (e: ChangeEvent) { contact_value = e.target.value; }}
                            />
                            <button className="btn primary full" onClick={next_contact}>
                                {"Continue" if contact_value.strip() else "Skip for now"}
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
                                placeholder="City, neighborhood, or ZIP"
                                onChange={lambda (e: ChangeEvent) { location = e.target.value; }}
                            />
                            <button className="btn primary full" onClick={use_manual_location} disabled={busy}>
                                {("Working…" if busy else "Continue") if location.strip() else ("Working…" if busy else "Skip for now")}
                            </button>
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
                    <div className="eyebrow">
                        {"Volunteer portal" if selected_role == "helper" else "Your private support space"}
                    </div>
                    <h1>
                        {"Sign in to help" if selected_role == "helper" else "Sign in to get support"}
                    </h1>
                    <label className="lbl" style={{"marginTop": "12px"}}>Email</label>
                    <input
                        className="field"
                        value={email}
                        placeholder="you@example.com"
                        onChange={lambda (e: ChangeEvent) { email = e.target.value; }}
                    />

                    <label className="lbl" style={{"marginTop": "12px"}}>Password</label>
                    <input
                        className="field"
                        type="password"
                        value={password}
                        onChange={lambda (e: ChangeEvent) { password = e.target.value; }}
                    />

                    <button
                        className="btn primary"
                        style={{"marginTop": "16px", "width": "100%"}}
                        onClick={do_login}
                        disabled={busy}
                    >
                        {"Working..." if busy else "Sign in"}
                    </button>

                    <button className="btn ghost full create-account" onClick={start_signup}>
                        Create new account
                    </button>

                    {if error {
                        <p className="err" key="e2" style={{"marginTop": "10px"}}>{error}</p>
                    }}

                </div>
            }}
        </div>
    </div>;
}
