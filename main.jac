"""Bridge - an agentic crisis navigator that quietly connects people who need
help to people who want to give it.

Server endpoints register by being named in the import list below, so that list
is the app's public API surface and nothing more. `EligibilityPathWalker`,
`NeedBroadcastWalker` and `StrategyWalker` are deliberately absent: they are
interior stages of the intake pipeline, spawned by the walkers that need them,
and exposing them as callable endpoints would have published three entry points
no client has any reason to hit.

    jac start --dev main.jac        # http://localhost:8000
"""

import from core.commons { bootstrap, choose_role, me, update_profile }
import from core.graph {
    AccountView, CommunityView, EngineReport, NeedCard, OfferView, OrgCard,
    PlanStep, PledgeCard, SeekerBoard, StrategyView, WalkerTrace
}
import from core.walkers {
    AnswerWalker, CommunityBoard, FollowUpWalker, FulfillmentWalker,
    HelperOfferWalker, IntakeWalker, MatchWalker, PledgeWalker,
    RetirePledgeWalker
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
