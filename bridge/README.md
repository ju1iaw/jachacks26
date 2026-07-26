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

### Turning the LLM on

Bridge ships with deterministic fallbacks for every model call, so it runs end to
end with **no API key at all** — but the badge in the UI turns red and reads
`DEGRADED`, and every fallback writes a line into the activity feed saying it
answered *instead of* the model. The fallbacks are a demo safety net, not a peer
of the model.

```bash
export OPENAI_API_KEY=sk-...
jac run scripts/verify_llm.jac     # exercises all 8 roles, fails if any fell back
./scripts/reset.sh                 # badge flips to `byLLM live - gpt-4o-mini`
```

`scripts/verify_llm.jac` is the answer to "is that really the model?" — it runs
every `by llm()` role once, prints the per-role call tally and the agent's tool
trace, and **exits non-zero** if anything was served heuristically. Set
`BRIDGE_STRICT_LLM=1` to make the fallbacks raise at the point of use instead of
substituting, so no answer can possibly be heuristic.

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
IntakeWalker              the person's words → a Person node
  │
  ├─ EligibilityPathWalker    Root → Org → Requirement. Reasons at every gate
  │                           with `by llm()`, and inserts an unblock step
  │                           directly above each org it blocks on.
  │
  ├─ NeedBroadcastWalker      turns each unmet category into an anonymized Need
  │                           on the commons and wires it to nearby orgs.
  │                           No push, no queue — the topology IS the message.
  │
  └─ StrategyWalker           hands the situation to a ReAct agent holding four
                              graph-reading tools, and stores both the strategy
                              it returns and the research path it chose.

MatchWalker               runs in the HELPER's session. Walks open needs,
                          soft-matches donor pledges with a second, different
                          `by llm()` role, writes a Matched edge, decrements
                          the pledge.

FulfillmentWalker         runs back in the SEEKER's session on their next poll.
                          Notices the Matched edge that appeared, rewrites the
                          plan, writes the nudge.

FollowUpWalker            ages open needs, then asks the model HOW to escalate —
                          widen the radius, reword the ask, or open a second
                          front in another category — and acts on the answer.
                          Its memory is a counter on the Need node.
```

`MatchWalker` and `FulfillmentWalker` never call each other. They run in
different sessions, in different HTTP requests, as different users. The only
thing they share is the graph — and that is enough for the seeker's plan to
rewrite itself seconds after a stranger clicks "match".

### Eight distinct `by llm()` roles

Not one prompt reused eight times — eight genuinely different reasoning jobs, each
with its own `sem` schema (`core/reason.jac`, plus the ReAct planner in
`core/agent.jac`):

| function | what it reasons about |
|---|---|
| `read_situation` | free text → structured facts, **and the anonymization itself** |
| `audit_anonymization` | an adversarial second pass that hunts identity leaks in the first one's output and repairs them |
| `ask_clarifying` | whether one missing fact would change the plan, and what to ask |
| `judge_requirement` | does *this* person's situation clear *this* org's gate, and what unblocks it |
| `judge_match` | does this pledge actually *help*, given the household's constraints |
| `plan_strategy` | **the ReAct agent** — researches the graph with tools, then commits to an ordered strategy |
| `escalation_strategy` | how to escalate a need nobody answered: wider, reworded, or a second front |
| `next_step_nudge` | the one line the person reads when their plan changes |

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
| `core/reason.jac` | seven `by llm()` roles, their `sem` schemas, the engine state machine, and the labelled fallbacks |
| `core/agent.jac` | the ReAct caseworker — the eighth role, plus its four graph-reading tools |
| `core/walkers.jac` | the seven walkers |
| `core/commons.jac` | accounts, roles, the shared commons and its seed data |
| `Shell/Gate/SeekerView/HelperView.jac` | the client, also Jac (compiles to React) |

```bash
jac check main.jac               # type-check everything
jac test                         # 15 tests (4 run the real by llm() path under MockLLM)
jac run scripts/smoke.jac        # whole walker chain on one local graph
jac run scripts/verify_llm.jac   # prove all 8 byLLM roles fire against the real key
```

## The 4-minute demo

1. **Who it's for.** "Maria has two kids, no ID, no car, and no food this week."
2. **Run it live.** Sign in as Maria → *Use the demo situation* → **Build my plan**.
   Point at the blocked food bank and the unblock step Bridge inserted above it.
3. **Flip to the other window.** Sam sees `N-XXXX — Needs groceries. Household of
   3; no way to cook.` and nothing else. Say the field-list line out loud.
4. **Click Run MatchWalker.** Read the rejection: right category, unusable, so it
   took the ready-to-eat boxes instead.
5. **Flip back to Maria without touching anything.** The plan has already
   rewritten itself — *"Good news — groceries is covered. Next up: ECS Navigation
   Center."* Nothing pushed it. `FulfillmentWalker` just read the graph.
6. **Kicker.** Back on Sam's side, **Simulate 48h with no help** → the shelter
   need escalates itself, and the model decides *how*: wider radius, reworded ask,
   or a second front in `legal` because stopping the eviction is what actually
   relieves the housing need. It remembers it escalated.

Show `core/walkers.jac` when they ask where Jac runs — and `core/agent.jac` for
the agent's tool trace. If anyone asks whether the reasoning is real, run
`jac run scripts/verify_llm.jac` on the spot: it names every role, counts the
calls, and exits non-zero if a single answer came from a fallback.
