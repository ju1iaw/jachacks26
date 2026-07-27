# Bridge — Full Product Description

## Product overview

**Bridge is an AI-assisted crisis navigation and community coordination platform
that helps people find practical support while giving local organizations
verifiable control over inventory, claims, and distributions.**

Its central promise is simple:

> Nobody has to ask for help alone.

People in crisis rarely need only a directory. They need to understand which
programs fit their situation, what they will be asked to bring, what to do when
they do not qualify, and whether help is actually available. At the same time,
volunteers want a safe and useful way to contribute, while organizations need
reliable operational counts rather than unverified self-reports.

Bridge connects those three groups in one system:

- A **person seeking help** describes what is happening in ordinary language
  and receives a private, prioritized action plan.
- A **volunteer** sees anonymized community needs and organization-calculated
  shortages, then offers relevant goods, services, time, or support.
- A trusted **organization** confirms what was actually received, what has been
  reserved, what a recipient claimed, and what was ultimately distributed.

The result is a feedback loop in which assistance is easier to discover,
community generosity is easier to direct, and real-world counts come from the
organizations in a position to verify them.

## The problem Bridge addresses

People navigating food insecurity, housing instability, eviction, unemployment,
or document loss often encounter several failures at once:

1. **Support is fragmented.** Food banks, shelters, legal clinics, workforce
   programs, and community groups publish information in different places.
2. **Eligibility is difficult to predict.** A person may travel to an
   organization only to discover that they need identification, proof of
   address, an appointment, or another document they do not have.
3. **Generic referrals are not plans.** A list of phone numbers does not explain
   what to do first, which blocker affects several options, or how to recover
   when one route fails.
4. **Community willingness is poorly connected to real demand.** Volunteers may
   want to help without knowing what is currently useful or where to take it.
5. **Self-reported fulfillment is not sufficiently trustworthy.** A volunteer
   saying “I donated this” or a recipient saying “I received this” should not
   automatically become an authoritative inventory transaction.
6. **Counts quickly become misleading.** Without a trusted ledger, systems
   cannot reliably distinguish an offer from a received donation, a reservation
   from a distribution, or historical service from current occupancy.

Bridge treats these as one connected coordination problem rather than separate
directory, chatbot, donation, and inventory products.

## Who Bridge serves

### People seeking help

The seeker experience is designed for someone who may be stressed, short on
time, or unfamiliar with social-service systems. The person can describe their
situation naturally—for example:

> I need food for me and my two children this week. I lost my ID, I do not have
> a car, and where we are staying has no stove. We also received an eviction
> notice.

Bridge turns that description into structured but private case information:

- categories of help needed;
- urgency;
- household size;
- practical constraints;
- assets or documents the person already has;
- a location reduced to the minimum service-area detail needed for routing;
- and an anonymized summary suitable for the shared community graph.

The person receives:

- a prioritized strategy rather than an unordered directory;
- organization recommendations grounded in their situation;
- clear eligibility status;
- specific explanations of blockers;
- practical steps for overcoming those blockers;
- addresses, phone numbers, and calling guidance;
- an ongoing list of accepted actions;
- a history of past suggestions;
- and follow-up updates when community or organization state changes.

If one unresolved fact would materially change the plan, Bridge asks one focused
question and explains why it matters. The answer is stored with the case and the
plan is rebuilt using the new information instead of merely appending generic
advice.

### Volunteers and community members

The volunteer experience answers two questions:

1. What do nearby organizations verifiably need?
2. How can I contribute in a way that is actually usable?

Volunteers see:

- organization-level opportunities calculated from verified inventory and open
  demand;
- the number of units still needed;
- the number of units requested and currently available;
- the receiving organization and its location;
- anonymized open needs;
- and the status of their own offers.

A volunteer can describe an offer conversationally, such as:

> I can cook and deliver meals for two households within ten miles on weekends.

Bridge uses a dedicated AI role to separate combined offers, classify each offer
by the outcome it supports, extract a conservative capacity, and preserve
constraints such as schedule, radius, dietary restrictions, or pickup
requirements.

Crucially, submitting an offer does **not** prove that anything was donated. A
new contribution begins in an `offered` state with zero verified inventory. The
volunteer can withdraw an offer while it is still pending, but cannot mark it
received, distributed, or fulfilled.

### Organizations

Organizations are the operational trust layer of Bridge.

Each approved organization operator is bound to one organization. Public signup
cannot self-assign the organization role or choose an arbitrary organization
ledger.

The organization console provides:

- authoritative tallies by supported item or service category;
- offers awaiting receipt confirmation;
- partially received and fully received quantities;
- inventory currently reserved for matched needs;
- recipient claims awaiting distribution;
- confirmed distributions;
- cumulative people served;
- current on-site or program occupancy;
- open demand;
- and the calculated shortfall that should be shown to volunteers.

An organization may support only a small number of meaningful ledger types. A
food organization might track meal boxes or groceries; a clothing program might
track clothing units; a shelter can track reserved capacity, distributions or
placements, and the current number of people being served.

## The verified contribution lifecycle

Bridge deliberately separates intent, receipt, reservation, claim, and
distribution.

### 1. Volunteer offer

The volunteer describes what they can provide. Bridge creates a contribution
record routed through an appropriate organization.

At this point:

- the contribution is an offer;
- confirmed units are zero;
- available verified units are zero;
- and it cannot satisfy a need.

### 2. Organization receipt

The receiving organization confirms the number of units that physically
arrived. Partial receipts are supported.

The confirmation:

- increments the contribution's confirmed and received units;
- increments the organization's `received` tally;
- changes the contribution to `partially_received` or `received`;
- and wakes the matcher because new verified supply is now available.

### 3. Reservation and matching

Bridge considers only organization-confirmed inventory. It evaluates whether
the contribution is practically usable for an anonymized need, not merely
whether both share a category.

For example, dry rice may be categorized as food but still be a poor match for a
household with no way to cook. A ready-to-eat meal delivery may be a strong
match.

When a match is made:

- units are reserved on the organization's ledger;
- the contribution's available units are reduced;
- the need records the responsible organization;
- and the recipient can see that appropriate help is available.

### 4. Recipient claim

The person seeking help may claim or accept the reserved opportunity. This is a
statement of intent to receive the assistance, not proof that distribution
occurred.

Claiming:

- changes the need from `matched` to `claimed`;
- records the claim time;
- increments the organization's claim tally;
- and places the claim in the organization console.

The recipient cannot mark the need fulfilled.

### 5. Organization-confirmed distribution

After the person receives the item or service, the organization confirms the
distribution.

That confirmation:

- reduces reserved units;
- increments distributed units;
- increments people served;
- marks the need fulfilled;
- and supplies the verified fulfillment note used to update the person's plan.

On the seeker's next refresh, Bridge reconciles the plan, marks relevant steps
covered, and re-runs strategic planning if the fulfillment changes what the
person should do next.

## How “needed from volunteers” is calculated

Volunteer demand is not derived from volunteer claims or recipient
self-verification.

For each organization and ledger category, Bridge calculates:

```text
available inventory = received - distributed - reserved

needed from volunteers = max(0, open demand - available inventory)
```

Open demand is derived from anonymized, currently open needs routed to that
organization. Matched, claimed, and fulfilled needs are not counted again as
uncovered demand.

This means the opportunity board changes as the real operational ledger changes:

- confirming a receipt increases available inventory;
- reserving inventory decreases availability;
- confirming distribution converts a reservation into a completed transaction;
- new open needs increase demand;
- and fulfilled or retired needs stop contributing to open demand.

The number shown to volunteers is therefore an organization-grounded shortfall,
not a sum of unverifiable promises.

## AI-assisted crisis navigation

Bridge uses multiple specialized AI roles rather than one general chatbot
prompt.

The AI system performs distinct jobs:

- **Situation reading:** turns free text into urgency, categories, household
  information, constraints, assets, and an anonymized summary.
- **Privacy auditing:** performs a second adversarial pass over the proposed
  public summary and repairs identifying leaks before publication.
- **Eligibility reasoning:** compares a person's known facts with an
  organization's actual requirements and published workarounds.
- **Strategic planning:** uses graph-reading tools to research organizations,
  requirements, workarounds, verified community supply, and competing demand
  before choosing an ordered plan.
- **Focused follow-up:** identifies the one unanswered fact that would
  materially change routing or eligibility.
- **Match judgment:** evaluates the practical fit between confirmed supply and
  an anonymized need, including constraints and safe unit allocation.
- **Escalation planning:** decides whether an unanswered need should be
  reworded, routed to a wider service area, or addressed through a second
  category.
- **Next-step messaging:** explains what the person should do after verified
  fulfillment.
- **Volunteer offer extraction:** converts conversational offers into structured
  services or goods with capacities and constraints.

Bridge fails loudly when the configured model is unavailable. It does not
silently substitute keyword rules and present them as AI reasoning. The product
also exposes the active model, call count, and per-role activity so model usage
can be audited during operation and demonstration.

## Adaptive planning and follow-up

The person's plan is a live graph, not a static chatbot response.

Bridge re-evaluates the plan when:

- the person first describes their situation;
- the person provides a meaningful follow-up answer;
- the person says their circumstances changed;
- an organization confirms fulfillment;
- or previously unreachable support becomes available.

Re-describing a situation retires the person's stale open needs before new ones
are published. If a retired need had reserved inventory, those units are
returned safely to the contribution and organization ledger. Legacy match
records created before organization ledgers existed are handled without
corrupting inventory.

Open needs also retain age and escalation history. If a need remains unanswered,
Bridge can widen its organization radius, improve the wording of the anonymized
request, or open another path—for example, treating eviction defense as a legal
route that may reduce an urgent shelter need.

## Live organization discovery

Bridge combines seeded organization records with live community-directory
lookups.

Before eligibility planning, it can search OpenStreetMap-backed Photon and
Overpass data for relevant services near the person's service area. Search
queries reflect both the requested categories and audience signals, such as
senior-focused food support.

Live results are normalized and upserted into the same organization graph used
by:

- eligibility evaluation;
- need routing;
- volunteer opportunities;
- organization ledgers;
- and the strategic planning agent.

This avoids maintaining a separate, disconnected recommendation list.

## Privacy and data boundaries

Bridge's privacy model is implemented in its graph topology and response types.

### Private identity

Identity-bearing nodes live on the authenticated user's private graph root:

- `Person` belongs to the seeker;
- `Donor` belongs to the volunteer;
- `Account` contains the user's role and private profile information.

These nodes are not placed on the shared commons.

### Shared boundary records

Only the records required for coordination are shared:

- organizations;
- organization requirements;
- anonymized needs;
- volunteer contribution records;
- organization tallies;
- and the edges required for routing and matching.

### No donor-to-recipient identity path

There is no graph edge connecting a donor identity to a person identity.
Volunteer-facing views receive a `NeedCard`, a deliberately restricted type
that has no fields for a recipient name, street address, phone number, email
address, or other direct identity.

The public need contains only operationally necessary information such as:

- an opaque need code;
- category;
- anonymized summary;
- urgency;
- household size;
- coarse service-area prefix;
- status;
- and the organization through which it is routed.

### Role enforcement

Protected backend walkers enforce account roles:

- seekers can run seeker intake, answers, claims, and board refreshes;
- helpers can view community opportunities and submit or withdraw their own
  pending offers;
- organization operators can mutate only their bound organization's receipts,
  occupancy, claims, and distributions.

Public signup supports seeker and helper accounts. Organization access is
provisioned through a trusted administrative path.

## Product experience

### Entry and account setup

The landing experience asks the user to choose between:

- **I need help right now**
- **I'm a volunteer**

Account setup supports email or phone authentication, optional contact
information, and location selection through browser geolocation, address
suggestions, or manual entry. Location is used to derive a service area for
routing rather than exposed directly to volunteers.

Seekers can enable quick access on a trusted device, update profile and
eligibility information, revisit past suggestions, or completely sign out.

### Seeker workspace

The seeker workspace centers on a conversational situation description and
renders the resulting plan as actionable cards. Cards distinguish between:

- programs the person appears eligible for;
- programs with a blocker;
- specific “qualify first” actions;
- matched community assistance;
- claimed assistance in progress;
- and completed or dismissed suggestions.

### Volunteer workspace

The volunteer workspace combines:

- a conversational “How can you help?” input;
- structured cards for the volunteer's active and past offers;
- tally-derived organization shortages;
- and anonymized open community needs.

### Organization workspace

The organization workspace is an operational ledger rather than a social feed.
Staff can:

- review incoming offers;
- confirm all or part of an offer received;
- view reserved and claimed needs;
- confirm actual distribution;
- update current occupancy;
- and see received, reserved, distributed, claim, service, demand, and shortfall
  metrics.

## Technical architecture

Bridge is implemented in Jac as a persistent graph application.

Core graph entities include:

- `Account`
- `Person`
- `Donor`
- `Org`
- `Requirement`
- `Contribution`
- `OrgTally`
- `Need`
- `PlanStep`
- `CaseStrategy`
- and `AnsweredQuestion`

Walkers perform state transitions by traversing this graph:

- `IntakeWalker`
- `EligibilityPathWalker`
- `NeedBroadcastWalker`
- `StrategyWalker`
- `AnswerWalker`
- `MatchWalker`
- `FulfillmentWalker`
- `FollowUpWalker`
- `HelperOfferWalker`
- `PledgeWalker`
- `OrganizationReceiptWalker`
- `OrganizationDistributionWalker`
- `OrganizationOccupancyWalker`
- `CommunityBoard`
- and `OrganizationBoard`

Matching is event-driven. It is awakened when verified supply, open demand, or
routing reachability changes rather than waiting for a user to press a separate
match button.

## Safety and integrity principles

Bridge is designed around several explicit integrity rules:

1. A volunteer offer is not a receipt.
2. A recipient claim is not a distribution.
3. Only a bound organization operator may confirm physical receipt or
   distribution.
4. Matching consumes only verified organization-held supply.
5. Reserved inventory cannot simultaneously count as available inventory.
6. Retiring a need returns its reservation.
7. Public needs are anonymized and structurally unable to contain direct
   identity fields.
8. AI failures are surfaced rather than replaced with fabricated certainty.
9. The strategic plan is refreshed when verified fulfillment makes the prior
   plan stale.
10. Volunteer opportunity counts never fall below zero.

## Current scope

The current product focuses on four outcome categories:

- food;
- shelter;
- legal assistance;
- and employment or job support.

The data model supports organization-specific ledger categories and can be
extended to clothing, hygiene supplies, transportation, childcare, medical
navigation, or other community resources.

Bridge currently demonstrates the full coordination model: private intake,
eligibility-aware planning, live organization discovery, anonymized demand,
volunteer offer extraction, organization-confirmed inventory, practical
matching, recipient claims, organization-confirmed distribution, occupancy
tracking, adaptive replanning, and auditable activity.

## Short description

Bridge is an AI-assisted crisis navigation platform that privately turns a
person's situation into an actionable support plan, shows volunteers what local
organizations verifiably need, and lets organizations maintain authoritative
counts of received, reserved, claimed, and distributed resources.

## One-sentence pitch

**Bridge turns a private request for help into a practical plan and a verified
community response, with local organizations—not volunteers or recipients—as
the source of truth for what was actually received and distributed.**
