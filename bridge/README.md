# Bridge

**Nobody has to ask for help alone.**

An agentic crisis navigator that gets people help — and quietly connects them to
someone who can give it. Built entirely in [Jac](https://docs.jaseci.org/).

---

## Run it

```bash
cd bridge
./scripts/reset.sh          # wipes the graph, starts the server, seeds demo accounts
open http://localhost:8000
```

Two demo accounts, password `bridge1234` for both:

| login | side |
|---|---|
| `maria@bridge.demo` | **person in need** — describes a situation, gets a live plan |
| `sam@bridge.demo` | **volunteer / donor** — sees anonymized needs, pledges, matches |

Open them in **two different browser profiles** (or one normal + one private
window) so both sessions are live at once — that's the demo.

Prefer the terminal? `./scripts/demo_flow.sh` drives the identical flow through
the REST API as two genuinely different logged-in users.

You only need `reset.sh` for a genuinely clean board. To run the demo again,
have Maria hit **Something's changed — redo this** — re-describing replans from
scratch and retires the asks already out on the commons for her.

### Turning the LLM on

**Bridge needs a key.** There are no heuristic fallbacks anywhere in it: every
judgement it makes about a person comes from the model or the call raises. A
`by llm()` role with no working connection fails loudly, before it touches the
graph, rather than quietly serving a guess that looks like reasoning.

```bash
export OPENAI_API_KEY=sk-...
jac run scripts/verify_llm.jac     # exercises all 7 roles, fails if any did not
./scripts/reset.sh                 # badge reads `byLLM live - gpt-4o-mini`
```

`scripts/verify_llm.jac` is the answer to "is that really the model?" — it runs
every `by llm()` role once, prints the per-role call tally and the agent's tool
trace, and **exits non-zero** if any role never reached the model or the ReAct
agent never touched the graph. The badge in the UI carries the same evidence
live: the model name and the running call count.

Note that `jac run` / `jac start` do **not** read `.env` — only
`scripts/reset.sh` sources it. Export the key in your shell for anything else.

Model is set in `jac.toml` under `[byllm.model]` and bound explicitly as a `glob
llm` in `core/reason.jac` (which is also what lets the tests swap in a
`MockLLM`). Anthropic / Google / Ollama work by setting their key instead.

---

## The problem

When someone hits a crisis, the help they need almost always already exists — a
food bank three miles away, a legal aid clinic, a neighbour with a spare bag of
groceries. Three things stand in the way:

1. **Eligibility is a maze.** Every org wants different things at the door — ID,
   proof of address, a booked appointment — and you find out you're missing one
   *after* you've made the trip.
2. **Needs and generosity never meet.** Plenty of people want to help locally,
   but there's no low-friction, private way to do it. Asking face to face is the
   single biggest barrier to actually getting help.
3. **Nobody follows up.** "Call this number" is not the same as getting fed.

Bridge solves all three as one connected system, because they're one problem.

## What it does

**For the person in crisis.** They type it plainly — *"I need food for me and my
two kids this week. I lost my ID, no car, and where we're staying has no stove."*
Bridge builds a live plan across food, shelter, legal and jobs, checks each org's
real requirements against their actual situation, and re-routes the moment it
hits a blocker:

```
[do this first] First: government-issued photo id
                Get a free California ID at the DMV on Fell St — fee waived
                with a shelter letter, same day.
[blocked]       Mission Community Food Bank
                Gate: Government-issued photo ID
[you qualify]   Bayview Free Pantry
                No-barrier pantry. No ID, no paperwork, no questions.
```

**For the community.** Every live need is anonymized and surfaced to local orgs
and their supporters. Donors pledge; Bridge matches pledges to needs on *fit*,
routes everything through the org as intermediary, and tells the person help is
coming — without ever revealing the donor, or revealing the recipient to the
donor.

## The privacy model is structural

This is the part that isn't a policy — it's the data model.

- **Identity nodes live on their owner's private root and are never granted.**
  `Person` sits on the seeker's root, `Donor` on the helper's. Neither is
  reachable from the other session, enforced by the runtime's permission model,
  not by us remembering to filter a field.
- **Only the boundary objects live on `root.shared`** — `Org`, `Requirement`,
  `Need`, `Contribution`.
- **No edge type connects a donor to a person.** From a `Need` the only way out
  is `BroadcastTo → Org`, and from an `Org` the only way to a pledge is back down
  `RoutedThrough`. There is no traversal that reaches a `Person`.
- **The donor-facing endpoint returns `NeedCard`, not `Need`** — a type with no
  field that could hold a name, address or contact. Run `./scripts/demo_flow.sh`
  and step 2 prints the complete field list.

## How it works

Everything is one persistent graph. Computation moves through it as **walkers**,
not as a pipeline of API calls.

```
IntakeWalker              the person's words → a Person node. One per root, so
  │                       describing again updates that Person rather than
  │                       minting a second one, and re-runs everything below.
  │
  ├─ EligibilityPathWalker    Root → Org → Requirement. Reasons at every gate
  │                           with `by llm()`, and inserts an unblock step
  │                           directly above each org it blocks on.
  │
  ├─ NeedBroadcastWalker      turns each unmet category into an anonymized Need
  │                           on the commons, wires it to nearby orgs, and wakes
  │                           the matcher on it. The topology IS the message.
  │
  └─ StrategyWalker           hands the situation to a ReAct agent holding four
                              graph-reading tools, and stores both the strategy
                              it returns and the research path it chose — plus
                              the one question its research left unresolved. Not
                              an endpoint: it is woken by intake, and again by
                              FulfillmentWalker when a match makes its brief
                              stale.

AnswerWalker              takes the answer to that question, records it on the
                          graph, folds it into the person's own words, and runs
                          the whole chain above again on the enriched story.

PledgeWalker              the donor side's only entry point: puts a pledge on
                          the shelf, routed through an org — and wakes the
                          matcher on it before it returns. There is no second
                          button.

MatchWalker               soft-matches open needs against donor pledges with a
                          second, different `by llm()` role, writes a Matched
                          edge, decrements the pledge. NOBODY RUNS IT — it is
                          woken by the graph events that change what a need can
                          reach (below).

FulfillmentWalker         runs back in the SEEKER's session on their next poll.
                          Notices the Matched edge that appeared, rewrites the
                          plan, writes the nudge — then wakes the caseworker,
                          because a brief reasoned over an open category is
                          wrong the moment that category is covered.

FollowUpWalker            ages open needs, then asks the model HOW to escalate —
                          widen the radius, reword the ask, or open a second
                          front in another category — and acts on the answer.
                          Its memory is a counter on the Need node.
```

### Matching is autonomous

There is no scheduler, no queue and no "match" button in the loop. `MatchWalker`
is woken by the three events that can change what a need is able to reach:

| trigger | woken by | what changed |
|---|---|---|
| a need lands on the commons | `NeedBroadcastWalker` | there is something new to fill |
| a pledge lands on the shelf | `PledgeWalker` | there is something new to fill it with |
| escalation widens the radius | `FollowUpWalker` | orgs that were out of range are now in it |

So whichever half of a match arrives second sets it off, in whichever session
that happened to be — Maria's own intake request matches her food need against a
standing pledge before she has finished reading her plan, and Sam's pledge
matches on arrival without him doing anything but submitting it.

Running the matcher from either side is safe for the same structural reason the
whole app is: from a `Need` the only way out is `BroadcastTo → Org`, and from an
`Org` the only way to a pledge is back down `RoutedThrough`. **Reachability is
what enforces the privacy boundary, not whose session the walker runs in** —
there is no session in which `MatchWalker` can reach a `Person`.

Each trigger is scoped to what actually changed rather than re-sweeping the
commons: the need-side passes the codes that just opened, and the pledge side
passes the pledge itself and lets `MatchWalker` walk *up* its `RoutedThrough`
edges and back down every `BroadcastTo` aimed at the same orgs. A trigger that
fails (a provider blip mid-match) is logged into the activity feed and swallowed
— the need simply stays open for the next trigger, and the helper's **Re-sweep
the commons** button is there as a manual backstop. It should find nothing to do.

`MatchWalker` and `FulfillmentWalker` still never call each other. They run in
different sessions, in different HTTP requests, as different users. The only
thing they share is the graph — and that is enough for the seeker's plan to
rewrite itself seconds after a stranger's pledge lands.

### So does the caseworker

The same rule governs the agent. `StrategyWalker` is not an endpoint and has no
button either — a brief is an answer to a question about the graph, so it stops
being true when the graph moves. Two events run it:

| trigger | woken by | what changed |
|---|---|---|
| the story is new or re-described | `IntakeWalker` | the facts it reasoned from |
| a need got covered | `FulfillmentWalker` | a category it planned around is closed, and the shelf it read is drawn down |

That second one is not decoration. The agent calls `check_shelf` and
`commons_pressure` as part of its research, so its brief is explicitly a
function of community state. Before this trigger existed, Maria's card still
read *"obtain a shelter letter to access food and shelter services without ID"*
after her food need had already been filled — advice premised on a category that
was no longer open. Now the fulfillment that invalidated it is what re-runs it,
on the same poll, and she is never shown a stale plan or asked to refresh one.

It only fires on the poll where something actually settled; the other ticks of
the 3s poll do no model work. And `StrategyWalker` retires the old brief **only
once the new one exists**, so a ReAct loop that fails mid-tool-call leaves the
previous brief on screen instead of blanking the card.

### Seven distinct `by llm()` roles

Not one prompt reused seven times — seven genuinely different reasoning jobs, each
with its own `sem` schema (`core/reason.jac`, plus the ReAct planner in
`core/agent.jac`):

| function | what it reasons about |
|---|---|
| `read_situation` | free text → structured facts, **and the anonymization itself** |
| `audit_anonymization` | an adversarial second pass that hunts identity leaks in the first one's output and repairs them |
| `judge_requirement` | does *this* person's situation clear *this* org's gate, and what unblocks it |
| `judge_match` | does this pledge actually *help*, given the household's constraints |
| `plan_strategy` | **the ReAct agent** — researches the graph with tools, then commits to an ordered strategy *and to the one question it still needs answered* |
| `escalation_strategy` | how to escalate a need nobody answered: wider, reworded, or a second front |
| `next_step_nudge` | the one line the person reads when their plan changes |

There used to be an eighth, `ask_clarifying`, and it is instructive that it is
gone — see [the question that asks itself](#the-question-that-asks-itself).

### The privacy claim is checked, not asserted

`read_situation` produces the anonymized summary; `audit_anonymization` is a
**second model pass whose only job is to catch it lying**. Whatever the auditor
repairs is what gets published to the commons, and what it caught is stored on the
`Person` node and rendered in the UI. So the demo shows the specific fragments —
a name, a street address, a phone number — that were stripped before any
volunteer could see them.

### The ReAct caseworker

`core/agent.jac` is the one place the model isn't answering a single well-posed
question. It gets four tools, each a **real graph read**, and decides for itself
what to investigate before committing to a plan:

| tool | what it reads |
|---|---|
| `survey_orgs(category)` | every org in a category and the gates each enforces |
| `inspect_gate(fragment)` | the published workaround for a blocking requirement |
| `check_shelf(category)` | what the community has pledged and still has available |
| `commons_pressure(category)` | how many other needs are competing right now |

Every invocation is recorded and stored on the `CaseStrategy` node, so the UI can
show the research path the agent *chose* to take — which lookups, in what order,
and what came back. Change the graph and the plan changes with it.

The matcher is the one to watch. A donor pledges *"40lb of dry rice, beans and
pasta"*; the need says *"household of 3, no way to cook"*. Same category, exact
keyword match — and Bridge **declines it**, then takes the ready-to-eat boxes
instead:

```
MATCHED N-F8AF -> 12 ready-to-eat family meal boxes, no cooking needed
PASSED  N-F8AF: passed on "40lb of dry rice, beans and pasta" --
        Technically the right category, but unusable for this household
        (no way to cook).
```

### The question that asks itself

Bridge asks the person at most one follow-up question, and **the agent that did
the research is the thing that asks it**. `plan_strategy` returns an
`open_question` alongside the brief, justified by a `question_why` that has to
name the organisation and requirement hinging on the answer.

This started as its own role, `ask_clarifying`, and it never once fired. The
reason is worth keeping: it was asked whether a missing fact "would change which
organisations this person is sent to" — while being handed no organisations and
no requirements. It had no basis to ever answer yes, so it always said no. The
judgement needs the org graph, and the agent already surveying the gates is the
only thing holding it. Deleting the role removed a model call *and* made the
question real.

Because it comes out of the research, the question can be specific about stakes:

```
One thing would change your plan
  Do you have any photo ID at all, even an expired one?
  Mission Community Food Bank and two others ask for photo ID at the door -- if
  you have one you can go tomorrow morning; if not, Bayview Free Pantry takes
  people with no paperwork at all.
```

Answering is not a form field. `AnswerWalker` records the Q&A as an
`AnsweredQuestion` node, folds the answer back into the person's own narrative,
and re-runs **the entire pipeline** on the enriched story — intake re-reads it,
every gate is re-judged, needs are rebuilt, and the agent writes a fresh
strategy. So "no, I don't have an ID" demotes every org that demands one and
promotes the no-barrier pantry, because those were always conclusions about the
graph rather than stored answers.

The `AnsweredQuestion` nodes are handed back to the agent on every answer-driven
re-plan, which is what stops it asking the same thing twice — and they render as
the *What you have told us* trail, so the person can see what their answers
changed. The one thing that clears them is the person re-describing their
situation by hand, which is how they take an answer back.

### Nothing about a plan is final

Situations move, and the version someone typed at 9am is not the one they are
living at noon. **Something's changed — redo this** sits on the plan itself and
reopens intake over it, pre-filled with the words that produced the plan on
screen. There is no separate edit flow: it is the same textarea and the same
`IntakeWalker`, which is what makes the update path trustworthy.

A person has exactly one `Person` node on their root, so a second submission
finds it and updates it rather than minting a second one. The three walkers
downstream each clear their own previous output before writing new output:

| what is rebuilt | who retires the old | why it matters |
|---|---|---|
| plan steps | `EligibilityPathWalker` | every gate is re-judged against the new facts, not patched |
| open needs | `IntakeWalker` | **the commons never carries two live asks for the same household** |
| answers given | `IntakeWalker` | restating your situation is how you *correct* an earlier answer |
| the agent's brief | `StrategyWalker` | the strategy is re-researched, including its one open question |

The needs line is the one that would hurt if it were missing. A `Need` is a node
on `root.shared` that donors can already see and pledge against — leaving a stale
one there means a volunteer doing real work against a request that no longer
exists. Retiring it deletes the node, which takes its `BroadcastTo` edges with
it, so it leaves the helper's board the moment the re-plan starts.

Retiring a need that was already **matched** has to give the donor their units
back. `MatchWalker` decremented `Contribution.remaining` when it wrote the
`Matched` edge, and deleting the need takes that edge with it — so without an
explicit credit the shelf would quietly drain by a few units on every
re-describe until the matcher started reporting that nothing fits, against
pledges nobody had actually used. The `Matched` edge carries the `units`, which
is what makes handing them back a lookup rather than a guess, and the return is
written into the activity feed so you can watch it happen.

The answers are cleared for the same reason the steps are. An `AnsweredQuestion`
is handed to the agent as established fact and is what stops it asking the same
thing twice — which is exactly wrong if the person came back specifically to say
their ID turned up. `AnswerWalker` is the one caller that passes
`keep_answers=True`, because the enriched story it submits already contains the
answer it just recorded.

Nothing that retires old state runs until the anonymization audit has come back.
The audit is a live model call and can fail on a provider blip; if it does, the
walker raises with the person's existing plan, needs and answers still intact,
rather than half-wiped. It is the same rule `EligibilityPathWalker` follows
before it clears the steps.

One client-side detail worth knowing if you touch `SeekerView.jac`: the `editing`
flag is **not** read off the board. The view polls `FulfillmentWalker` every 3
seconds and applies whatever comes back, so a server-derived flag would close the
textarea under someone mid-sentence. For the same reason the poll only re-syncs
the textarea from the graph while the box is *not* being edited — which also
means backing out with **Keep the plan I have** discards the edit.

The practical upshot for the demo: `./scripts/reset.sh` is for a clean board, not
for a second run. Maria can re-describe her situation and watch the whole
pipeline reason again from scratch, live, without anyone touching `.jac/`.

### Parallel gate checks

One org's requirements are independent, so `EligibilityPathWalker` launches every
judgement at once with `flow` and collects with `wait` — N sequential model round
trips become one. Same for the matcher scoring pledges.

⚠️ The `launch_requirement` / `launch_match` wrappers in `core/reason.jac` are
load-bearing: `flow` inside a comprehension captures the loop variable **by
reference**, so inlining them makes every future read the last item — which
silently turns blocked orgs into "you qualify". `core/reason.test.jac` has
regression tests for exactly this.

## Where the Jac is

| file | what's in it |
|---|---|
| `core/graph.jac` | every node, edge and view model — the privacy boundary is here |
| `core/reason.jac` | six single-shot `by llm()` roles, their `sem` schemas, and the engine state machine |
| `core/agent.jac` | the ReAct caseworker — the seventh role, plus its four graph-reading tools |
| `core/question_guard.jac` | the deterministic vet on what the agent may ask a person |
| `core/walkers.jac` | the eight walkers |
| `core/commons.jac` | accounts, roles, the shared commons and its seed data |
| `Shell/Gate/SeekerView/HelperView.jac` | the client, also Jac (compiles to React) |

```bash
jac check main.jac               # type-check everything
jac test                         # the suite (4 run the real by llm() path under MockLLM)
jac run scripts/smoke.jac        # whole walker chain on one local graph
jac run scripts/verify_llm.jac   # prove all 7 byLLM roles fire against the real key
jac run scripts/verify_redescribe.jac   # prove re-describing cleans up after itself
```

## The 4-minute demo

1. **Who it's for.** "Maria has two kids, no ID, no car, and no food this week."
2. **Run it live.** Sign in as Maria → *Use the demo situation* → **Build my plan**.
   Point at the blocked food bank and the unblock step Bridge inserted above it.
3. **Answer the agent's one question.** Read the *why* line out loud first — it
   names the orgs and the gate that hinge on the answer. Click **No**. The whole
   plan re-reasons on it: the orgs that demand ID drop down the list, the
   no-barrier pantry comes up, and the answer is now in *What you have told us*
   so it will never be asked again.
4. **Flip to the other window.** Sam sees `N-XXXX — Needs groceries. Household of
   3; no way to cook.` and nothing else. Say the field-list line out loud.
5. **Point at the status: it is already matched, and Sam never clicked anything.**
   The need woke the matcher the moment it landed, inside Maria's own request.
   Read the rejection out of the activity feed: right category, unusable, so it
   took the ready-to-eat boxes instead. Then have Sam pledge something for the
   *shelter* need and watch it match on submit — the trigger works from both
   ends, whichever half arrives second.
6. **Flip back to Maria without touching anything.** The plan has already
   rewritten itself — *"Good news — groceries is covered. Next up: ECS Navigation
   Center."* Nothing pushed it. `FulfillmentWalker` just read the graph. Point at
   the caseworker card above it too: the agent re-ran itself on the covered
   category, so the strategy is about what is *left*, not what she first typed.
7. **Kicker.** Back on Sam's side, **Simulate 48h with no help** → the shelter
   need escalates itself, and the model decides *how*: wider radius, reworded ask,
   or a second front in `legal` because stopping the eviction is what actually
   relieves the housing need. It remembers it escalated.

If you have time for one more, or someone asks "what if her situation changes?":
on Maria's plan, **Something's changed — redo this** reopens intake on the words
she typed the first time. Add a line — *"my sister can take the kids for a week"*
— and the whole pipeline runs again on it. Watch Sam's board while you do:
the stale needs disappear from the commons as the new plan is built, so nobody is
ever left working an ask that no longer exists.

Show `core/walkers.jac` when they ask where Jac runs — and `core/agent.jac` for
the agent's tool trace. If anyone asks whether the reasoning is real, run
`jac run scripts/verify_llm.jac` on the spot: it names every role, counts the
calls, and exits non-zero if any of them never reached the model.
