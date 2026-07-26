"""Bridge - the shell. Decides which of the two worlds you are looking at."""

import from "@jac/runtime" { jacIsLoggedIn, jacLogout }
import from .components.Bits { Brand, Pill }
import from .Gate { Gate }
import from .SeekerView { SeekerView }
import from .HelperView { HelperView }

sv import from .core.commons { me }
sv import from .core.graph { AccountView }


def:pub Shell -> JsxElement {
    has role: str = "";
    has display_name: str = "";
    has contact_method: str = "";
    has contact_value: str = "";
    has location: str = "";
    has ready: bool = False;
    has signed_in: bool = False;
    has seeker_panel: str = "home";

    async def load -> None;
    def sign_out(e: MouseEvent) -> None;
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

    if role == "seeker" {
        return <div>
            <div className="topbar seeker-topbar">
                <div className="icon-group">
                    <button
                        className={"icon-btn" + (" on" if seeker_panel == "settings" else "")}
                        type="button"
                        title="Settings"
                        aria-label="Settings"
                        onClick={open_settings}
                    >
                        <span className="icon-glyph" aria-hidden="true">⚙</span>
                    </button>
                    <button
                        className="icon-btn"
                        type="button"
                        title="Logout"
                        aria-label="Logout"
                        onClick={sign_out}
                    >
                        <span className="icon-glyph" aria-hidden="true">⎋</span>
                    </button>
                </div>

                <div className="spacer"></div>
                <Brand tagline="you need help"/>
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
                contact_method={contact_method}
                contact_value={contact_value}
                location={location}
                panel={seeker_panel}
                onHome={go_home}
            />
        </div>;
    }

    return <div>
        <div className="topbar">
            <Brand tagline="you are helping"/>
            <div className="spacer"></div>
            <Pill text={"volunteer · " + display_name} tone="cool"/>
            <button className="btn ghost sm" onClick={sign_out}>Sign out</button>
        </div>
        <HelperView key="h" display_name={display_name}/>
    </div>;
}
