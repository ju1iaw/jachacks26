"""Bridge - the shell. Decides which of the two worlds you are looking at."""

import from "@jac/runtime" { jacIsLoggedIn, jacLogout }
import from .components.Bits { Brand, Pill }
import from .Gate { Gate }
import from .SeekerView { SeekerView }
import from .HelperView { HelperView }
import from .OrganizationView { OrganizationView }

sv import from .core.commons { me }
sv import from .core.graph { AccountView }


def:pub Shell -> JsxElement {
    has role: str = "";
    has display_name: str = "";
    has contact_method: str = "";
    has contact_value: str = "";
    has email: str = "";
    has phone: str = "";
    has location: str = "";
    has eligibility_notes: str = "";
    has ready: bool = False;
    has signed_in: bool = False;
    has seeker_panel: str = "home";
    has quick_access: bool = True;
    has locked: bool = False;

    async def load -> None;
    def sign_out(e: MouseEvent) -> None;
    def sign_out_completely(e: MouseEvent) -> None;
    def continue_quick_access(e: MouseEvent) -> None;
    def set_quick_access(enabled: bool) -> None;
    def open_settings(e: MouseEvent) -> None;
    def open_past(e: MouseEvent) -> None;
    def go_home -> None;

    async can with entry {
        load();
    }

    if not signed_in {
        return <Gate onReady={load}/>;
    }
    if not ready {
        return <div className="empty"><span className="spin">◇</span> loading your graph...</div>;
    }
    if not role {
        return <Gate onReady={load}/>;
    }

    if role == "seeker" and locked {
        return <div className="quick-lock">
            <div className="quick-lock-card">
                <Brand tagline="private support, when you need it"/>
                <div className="eyebrow" style={{"marginTop": "28px"}}>Quick access</div>
                <h1>Bridge is ready when you are.</h1>
                <p className="muted">
                    Continue without entering a password on this trusted device.
                </p>
                <button className="btn primary full" type="button" onClick={continue_quick_access}>
                    Continue to Bridge
                </button>
                <button className="text-btn" type="button" onClick={sign_out_completely}>
                    Sign out completely
                </button>
                <p className="small muted quick-lock-note">
                    Complete sign-out removes quick access and requires your password next time.
                </p>
            </div>
        </div>;
    }

    if role == "seeker" {
        return <div>
            <div className="topbar seeker-topbar">
                <div className="icon-group">
                    <button
                        className={"icon-btn settings" + (" on" if seeker_panel == "settings" else "")}
                        type="button"
                        title="Settings"
                        aria-label="Settings"
                        onClick={open_settings}
                    >
                        <span className="icon-glyph settings" aria-hidden="true">⚙</span>
                    </button>
                    <button
                        className="icon-btn"
                        type="button"
                        title={"Leave Bridge" if quick_access else "Sign out"}
                        aria-label={"Leave Bridge" if quick_access else "Sign out"}
                        onClick={sign_out}
                    >
                        <span className="icon-glyph" aria-hidden="true">⎋</span>
                    </button>
                </div>

                <div className="spacer"></div>
                <Brand tagline="get support"/>
                <div className="spacer"></div>

                <button
                    className={"icon-btn" + (" on" if seeker_panel == "past" else "")}
                    type="button"
                    title="All past suggestions"
                    aria-label="All past suggestions"
                    onClick={open_past}
                >
                    <span className="icon-glyph list" aria-hidden="true">☰</span>
                </button>
            </div>
            <SeekerView
                key="s"
                display_name={display_name}
                email={email}
                phone={phone}
                location={location}
                eligibility_notes={eligibility_notes}
                quick_access={quick_access}
                panel={seeker_panel}
                onHome={go_home}
                onProfileSaved={load}
                onQuickAccessChange={set_quick_access}
            />
        </div>;
    }

    if role == "organization" {
        return <div>
            <div className="topbar">
                <Brand tagline="community operations"/>
                <div className="spacer"></div>
                <Pill text={"organization · " + display_name} tone="cool"/>
                <button className="btn ghost sm" onClick={sign_out_completely}>Sign out</button>
            </div>
            <OrganizationView key="org"/>
        </div>;
    }

    return <div>
        <div className="topbar">
            <Brand tagline="help your community"/>
            <div className="spacer"></div>
            <Pill text={"volunteer · " + display_name} tone="cool"/>
            <button className="btn ghost sm" onClick={sign_out}>Sign out</button>
        </div>
        <HelperView key="h" display_name={display_name}/>
    </div>;
}
