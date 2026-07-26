"""Bridge - an agentic crisis navigator that quietly connects people who need
help to people who want to give it.

Server endpoints register by being named in the import list below. The client
half is the `cl` block at the bottom.

    jac start --dev main.jac        # http://localhost:8000
"""

import from core.commons { bootstrap, choose_role, me }
import from core.graph {
    AccountView, CommunityView, EngineReport, NeedCard, OrgCard, PlanStep,
    PledgeCard, SeekerBoard, StrategyView, WalkerTrace
}
import from core.walkers {
    CommunityBoard, EligibilityPathWalker, FollowUpWalker, FulfillmentWalker,
    IntakeWalker, MatchWalker, NeedBroadcastWalker, PledgeWalker, StrategyWalker
}
import from core.reason { ensure_engine }


# Plant the orgs and their eligibility gates once, at boot.
with entry {
    bootstrap();

    # Fail loudly in the server log at startup, not just on the first request.
    # There is no fallback path in this app -- if this prints "unconfigured",
    # every feature that touches the model will error until a key is set.
    mode = ensure_engine();
    if mode != "llm" {
        print(f"[bridge] *** starting with NO working model connection (mode={mode}) ***");
        print("[bridge] *** set OPENAI_API_KEY / ANTHROPIC_API_KEY / GOOGLE_API_KEY and restart ***");
    }
}


cl {
    import "./styles/global.css";
    import from .Shell { Shell }

    def:pub app -> JsxElement {
        return <Shell/>;
    }
}
