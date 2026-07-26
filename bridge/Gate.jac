"""Bridge - sign in / sign up, and the one question that splits the app in two.

Which side of Bridge you are on is not a UI toggle: it writes an `Account` node
onto your own root, and from then on every walker you spawn runs against your
graph, not anyone else's.
"""

import from "@jac/runtime" { jacLogin, jacSignup }
import from .components.Bits { Brand }

sv import from .core.commons { choose_role }
sv import from .core.graph { AccountView }


def:pub Gate(onReady: Callable[[], None]) -> JsxElement {
    has mode: str = "login";
    has email: str = "";
    has password: str = "";
    has display_name: str = "";
    has role: str = "";
    has stage: str = "creds";
    has busy: bool = False;
    has error: str = "";

    async def do_login -> None;
    async def do_signup -> None;
    async def pick_seeker -> None;
    async def pick_helper -> None;
    def to_login(e: MouseEvent) -> None;
    def to_signup(e: MouseEvent) -> None;
    def fill_seeker(e: MouseEvent) -> None;
    def fill_helper(e: MouseEvent) -> None;

    return <div className="gate">
        <div style={{"marginBottom": "18px", "justifyContent": "center", "display": "flex"}}>
            <Brand tagline="nobody has to ask for help alone"/>
        </div>

        <div className="card">
            {if stage == "role" {
                <div key="role">
                    <h1>One question.</h1>
                    <p className="muted small" style={{"marginBottom": "18px"}}>
                        Which side are you here for? You can only be on one.
                    </p>
                    <div className="stack">
                        <button className="role-opt warm" onClick={pick_seeker} disabled={busy}>
                            <span className="glyph">◆</span>
                            <span>
                                <b>I need help right now</b>
                                <div className="small muted">
                                    Food, a place to stay, legal trouble, work. You describe it
                                    once and Bridge works out who will actually take you.
                                </div>
                            </span>
                        </button>
                        <button className="role-opt cool" onClick={pick_helper} disabled={busy}>
                            <span className="glyph">◇</span>
                            <span>
                                <b>I want to help someone</b>
                                <div className="small muted">
                                    See what your neighbours actually need this week, privately,
                                    and put something on the shelf for them.
                                </div>
                            </span>
                        </button>
                    </div>
                    {if error {
                        <p className="err" key="e" style={{"marginTop": "12px"}}>{error}</p>
                    }}
                </div>
                skip;
            }}

            <div className="tabs" style={{"marginBottom": "18px"}}>
                <button className={"on" if mode == "login" else ""} onClick={to_login}>Sign in</button>
                <button className={"on" if mode == "signup" else ""} onClick={to_signup}>Create account</button>
            </div>

            {if mode == "signup" {
                <div key="n">
                    <label className="lbl">What should we call you</label>
                    <input
                        className="field"
                        value={display_name}
                        placeholder="First name is plenty"
                        onChange={lambda (e: ChangeEvent) { display_name = e.target.value; }}
                    />
                </div>
            }}

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
                onClick={do_signup if mode == "signup" else do_login}
                disabled={busy}
            >
                {"Working..." if busy else ("Create account" if mode == "signup" else "Sign in")}
            </button>

            {if error {
                <p className="err" key="e2" style={{"marginTop": "10px"}}>{error}</p>
            }}

            <div className="demo-box">
                <b>Demo accounts</b>
                <div style={{"marginTop": "6px"}}>
                    <code>maria@bridge.demo</code>{" - the person in need  "}
                    <button className="btn ghost sm" onClick={fill_seeker}>use</button>
                </div>
                <div style={{"marginTop": "5px"}}>
                    <code>sam@bridge.demo</code>{" - the volunteer  "}
                    <button className="btn ghost sm" onClick={fill_helper}>use</button>
                </div>
                <div style={{"marginTop": "6px"}}>{"password for both: bridge1234"}</div>
            </div>
        </div>
    </div>;
}
