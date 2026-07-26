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
    has ready: bool = False;
    has signed_in: bool = False;

    async def load -> None;
    def sign_out(e: MouseEvent) -> None;

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

    return <div>
        <div className="topbar">
            <Brand tagline={"you need help" if role == "seeker" else "you are helping"}/>
            <div className="spacer"></div>
            <Pill
                text={("person in need" if role == "seeker" else "volunteer") + " · " + display_name}
                tone={"warm" if role == "seeker" else "cool"}
            />
            <button className="btn ghost sm" onClick={sign_out}>Sign out</button>
        </div>
        {if role == "seeker" {
            <SeekerView key="s" display_name={display_name}/>
        } else {
            <HelperView key="h" display_name={display_name}/>
        }}
    </div>;
}
