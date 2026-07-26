"""Bridge - an agentic crisis navigator that quietly connects people who need
help to people who want to give it.

Server endpoints register by being named in the import list below. The client
half is the `cl` block at the bottom.

    jac start --dev main.jac        # http://localhost:8000
"""

import from core.commons { bootstrap, choose_role, me }
import from core.graph {
    AccountView, CommunityView, NeedCard, OrgCard, PlanStep, PledgeCard,
    SeekerBoard, WalkerTrace
}
import from core.walkers {
    CommunityBoard, EligibilityPathWalker, FollowUpWalker, FulfillmentWalker,
    IntakeWalker, MatchWalker, NeedBroadcastWalker, PledgeWalker
}


# Plant the orgs and their eligibility gates once, at boot.
with entry {
    bootstrap();
}


cl {
    import "./styles/global.css";
    import from .Shell { Shell }

    def:pub app -> JsxElement {
        return <Shell/>;
    }
}
