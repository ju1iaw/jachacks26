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
end with **no API key at all** — the badge in the UI reads `reasoning: heuristic`.
Drop in a key and the same code paths switch to real reasoning:

```bash
cp .env.example .env        # add OPENAI_API_KEY=sk-...
./scripts/reset.sh          # sources .env, badge flips to `reasoning: llm`
```

Model is set in `jac.toml` under `[byllm.model]`. Anthropic / Google / Ollama
work by setting their key instead — see `core/reason.jac`.

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
  └─ NeedBroadcastWalker      turns each unmet category into an anonymized Need
                              on the commons and wires it to nearby orgs.
                              No push, no queue — the topology IS the message.

MatchWalker               runs in the HELPER's session. Walks open needs,
                          soft-matches donor pledges with a second, different
                          `by llm()` role, writes a Matched edge, decrements
                          the pledge.

FulfillmentWalker         runs back in the SEEKER's session on their next poll.
                          Notices the Matched edge that appeared, rewrites the
                          plan, writes the nudge.

FollowUpWalker            ages open needs and widens the broadcast radius on its
                          own. Its memory is a counter on the Need node.
```

`MatchWalker` and `FulfillmentWalker` never call each other. They run in
different sessions, in different HTTP requests, as different users. The only
thing they share is the graph — and that is enough for the seeker's plan to
rewrite itself seconds after a stranger clicks "match".

### Four distinct `by llm()` roles

Not one prompt reused four times — four genuinely different reasoning jobs, each
with its own `sem` schema (`core/reason.jac`):

| function | what it reasons about |
|---|---|
| `read_situation` | free text → structured facts, **and the anonymization itself** |
| `judge_requirement` | does *this* person's situation clear *this* org's gate, and what unblocks it |
| `judge_match` | does this pledge actually *help*, given the household's constraints |
| `next_step_nudge` | the one line the person reads when their plan changes |

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
| `core/reason.jac` | the four `by llm()` roles, their `sem` schemas, and heuristic fallbacks |
| `core/walkers.jac` | the six walkers |
| `core/commons.jac` | accounts, roles, the shared commons and its seed data |
| `Shell/Gate/SeekerView/HelperView.jac` | the client, also Jac (compiles to React) |

```bash
jac check .                      # type-check everything
jac test                         # 8 tests
jac run scripts/smoke.jac        # whole walker chain on one local graph
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
   need escalates its own broadcast radius, and remembers it did.

Show `core/walkers.jac` when they ask where Jac runs.
