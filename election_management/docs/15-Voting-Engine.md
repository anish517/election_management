# 15. Voting Engine

## 15.1 Purpose

Defines every supported voting method's ballot shape, validation rules, and tally algorithm. Each `Position` selects exactly one method (see `08-Database-Design.md` `positions.voting_method`).

**MVP (v1.0)**: FPTP, Multiple Choice.
**v1.1+**: Ranked Choice (STV), Approval, Weighted, Proxy, Yes/No — designed here now so the `votes.choice_data` schema and tally-service interface don't need breaking changes later.

## 15.2 First-Past-The-Post (FPTP) — Single Choice

- **Ballot**: voter selects exactly 1 candidate for a position with 1 seat.
- **`choice_data` shape**: `{"candidate_id": "<uuid>"}`
- **Tally**: candidate with the most votes wins. Tie → see §15.9.

## 15.3 Multiple Choice (Block Voting)

- **Ballot**: voter selects up to N candidates for a position with N seats (e.g., "Executive Member" with 3 seats — voter picks up to 3).
- **`choice_data` shape**: `{"candidate_ids": ["<uuid>", "<uuid>"]}`
- **Validation**: `len(candidate_ids) <= position.seats_available`; no duplicates.
- **Tally**: top N candidates by vote count fill the N seats.

## 15.4 Ranked Choice Voting (RCV) / Single Transferable Vote (STV)

- **Ballot**: voter ranks candidates in order of preference (1st, 2nd, 3rd...).
- **`choice_data` shape**: `{"ranking": ["<uuid_1st>", "<uuid_2nd>", "<uuid_3rd>"]}`
- **Tally (single-seat, Instant Runoff)**:
  1. Count first-preference votes.
  2. If a candidate has >50%, they win.
  3. Otherwise, eliminate the lowest-scoring candidate, redistribute their ballots to voters' next preference, repeat.
- **Tally (multi-seat, STV)**: Droop quota `= floor(valid_votes / (seats + 1)) + 1`; candidates meeting quota are elected, surplus votes transfer at a fractional weight, lowest candidate eliminated each round if no one meets quota, repeat until all seats filled.
- **Exhausted ballots** (a ballot whose ranked candidates are all eliminated/elected before all seats fill) are tracked separately and reported, not silently dropped from turnout statistics.

## 15.5 Approval Voting

- **Ballot**: voter marks "approve" on any number of candidates (no ranking, no limit).
- **`choice_data` shape**: `{"approved_candidate_ids": ["<uuid>", ...]}`
- **Tally**: candidate(s) with the most approvals win the available seats.

## 15.6 Yes/No (Referendum-style)

- Used for resolutions, budget approval, constitutional amendments — not candidate elections.
- **Ballot**: voter selects `Yes`, `No`, or (if enabled) `Abstain`.
- **`choice_data` shape**: `{"answer": "yes" | "no" | "abstain"}`
- **Tally**: simple majority by default; **super-majority threshold configurable** per position (e.g., constitutional changes commonly require 66.7%+) — abstentions excluded from the denominator by default, configurable.

## 15.7 Weighted Voting

- Used where voting power varies by shareholding, membership tier, or delegate count (common in cooperatives and corporate contexts).
- Each `Member` carries a `voting_weight` (decimal, default 1.0) sourced from the org's member data (e.g., number of shares).
- **`choice_data` shape**: same as the underlying method (FPTP/Multi-choice/etc.); the *weight* is applied at tally time, not stored per-ballot, keeping the anonymized `votes` table (§8.2 of `08-Database-Design.md`) free of any identity-correlating weight lookup — the tally service joins `voter_rolls.member_id → members.voting_weight` **before** anonymization is broken, i.e., weight is resolved and baked into the tally computation at cast-time, not retroactively joined against the anonymized ballot afterward.
- **Tally**: `Σ(voting_weight)` per candidate rather than a raw count.

## 15.8 Proxy Voting

- A member may (if the org's rules permit) delegate their vote to another eligible member for a specific election.
- **Proxy assignment**: recorded in a separate `proxy_assignments` table (`grantor_member_id`, `proxy_member_id`, `election_id`, `assigned_at`, `revoked_at`) — **not** part of the anonymized `votes`/`voter_rolls` schema, since a proxy relationship is itself sensitive but pre-vote metadata, not ballot content.
- At vote-casting time, the proxy-holder casts one ballot per delegation they hold, plus their own — each recorded as a separate anonymized `votes` row against the respective `voter_rolls` entries (the grantor's roll entry is marked `has_voted` when their proxy votes on their behalf).
- Proxy assignments are revocable by the grantor up until the proxy actually casts the vote.

## 15.9 Tie-Breaking

Configurable per organization, applied in this default order unless overridden:

1. **Recount** — automatic single recount of the tied position.
2. **Runoff** — if the org enables it, a follow-up election among tied candidates only (new short voting window).
3. **Lot (random draw)** — last resort, performed by the Election Officer in front of an Auditor, logged with a cryptographically-seeded random draw for reproducibility/verifiability, never a manual "coin flip" outside the system.

## 15.10 Tally Service Interface

```python
def tally_position(position: Position) -> TallyResult:
    """Dispatches to the correct algorithm based on position.voting_method.
    Reads anonymized votes.choice_data for the position, applies
    voting_weight if applicable, returns TallyResult(winners, full_breakdown,
    exhausted_ballot_count, tie_detected)."""
```

All algorithms are implemented as pure functions taking a list of anonymized `choice_data` dicts (+ optional weight map) and returning a deterministic result — this makes them independently unit-testable and independently re-runnable by an Auditor for verification (`19-Audit-Compliance.md`) without needing access to any voter-identifying data.

Continue to `16-Ballot-Builder.md`.
