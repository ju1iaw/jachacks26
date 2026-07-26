"""Bridge - what the caseworker agent is allowed to ask a person in crisis.

`core/agent.jac` lets the model decide the single follow-up question worth putting
to someone mid-crisis, and the rules governing that question are lines in a
prompt. A prompt is not an enforcement mechanism. Both of the questions below were
produced by gpt-4o-mini with the rule forbidding them already in the prompt:

    "What is the current address or location where the person is staying?"
    "How will you obtain proof of address for food assistance?"

The first collects an identifying detail at the source, before the anonymizer ever
sees it, which undoes the promise the whole service runs on. The second hands
Bridge's own research back to the person -- the agent has `inspect_gate` for
exactly that and is supposed to have used it.

So the question is vetted deterministically before anyone sees it. This is the
same shape as `judge_match_safe` clamping the model's unit allocation: it only
ever DROPS a question, never rewrites one and never invents one. A dropped
question costs nothing -- the strategy is complete without it -- so a false
positive here is cheap and a false negative is not.

This module deliberately imports nothing. It is pure string policy, which keeps it
testable on its own and keeps `core/question_guard.test.jac` from dragging the
whole reasoning layer in behind it.
"""

glob IDENTIFYING_DETAILS: list[str] = [
    "address",
    "zip",
    "postcode",
    "post code",
    "street",
    "phone number",
    "name",
    "employer",
    "school",
    "social security number"
];

"""Openers that demand a value rather than a yes or no."""
glob VALUE_OPENERS: list[str] = ["what ", "what's ", "where ", "which ", "who "];

"""Phrasings that ask the person to work out something the agent should look up."""
glob RESEARCH_OFFLOADS: list[str] = [
    "how will you",
    "how would you",
    "how do you plan",
    "how are you going to",
    "how can you get",
    "how can you obtain",
    "how do you intend",
    "what is the best way",
    "what's the best way"
];


"""Say what is wrong with this question, or "" if it is fit to ask.

The reason reads as the tail of "the agent tried to ask this person ...", so the
caller can log why the guard fired without restating the two cases.

Two ways a question fails. It can **solicit an identifying value** -- and the
distinction that matters there is a value versus a document: "What is your
address?" collects an identifying detail, while "Do you have any mail showing
your address?" asks about a piece of paper they either have or do not, which is
exactly what a caseworker should ask. Both mention an address, so the opener is
what separates them.

Or it can **hand back the research**. "How will you obtain proof of address?"
asks someone in a crisis to solve the problem they came here with.
"""
def unfit_question(question: str) -> str {
    q = " ".join(question.lower().split());

    for phrase in RESEARCH_OFFLOADS {
        if phrase in q {
            return "to do the research it has tools for";
        }
    }

    # A bare "Where ...?" solicits a location whatever follows it. "Can you get a
    # letter from where you are staying?" does not, and does not open on it.
    if q.startswith("where ") {
        return "for their location";
    }

    demands_value = False;
    for opener in VALUE_OPENERS {
        if q.startswith(opener) {
            demands_value = True;
        }
    }
    if not demands_value {
        return "";
    }

    for term in IDENTIFYING_DETAILS {
        if term in q {
            return f"for their {term}";
        }
    }
    return "";
}
