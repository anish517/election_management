# 16. Ballot Builder

## 16.1 Purpose

The Election Officer-facing tool for configuring exactly how a ballot renders to voters — separate from the underlying voting-method logic (`15-Voting-Engine.md`), which handles *what happens* with a submission; this module handles *what the voter sees*.

## 16.2 Ballot Composition

- A ballot is generated per-election, per-voter, at render time (not pre-generated and stored) — pulling: approved candidates only (per `14-Candidate-Management.md`), in the configured ordering (§14.7), filtered to the positions that voter is eligible to vote in.
- Multi-position elections render as a single scrollable ballot with clear section breaks per position, not separate ballots per position — reduces voter drop-off between positions.

## 16.3 Configurable Elements

| Element | Options |
|---|---|
| Candidate display | Photo + name, or Photo + name + symbol |
| Language | Bilingual (Nepali primary / English secondary, or reverse) toggle, or single-language lock |
| Ordering | Alphabetical, randomized, manual |
| "None of the above" / abstain option | On/off per position |
| Write-in candidates | Off by default (adds significant validation/eligibility complexity); available as a v1.1+ configurable option for org types that require it |
| Manifesto access | Inline summary + "view full manifesto" link, or full manifesto shown inline |

## 16.4 Validation Rules (Client + Server)

- Client-side (Flutter): immediate feedback — e.g., block submission if more than `seats_available` selected for Multiple Choice.
- Server-side (authoritative): every client-side rule is re-validated in `services.py` before a vote is accepted — the client validation is a UX convenience, never trusted as the sole gate (consistent with §9.3's defense-in-depth principle).

## 16.5 Accessibility

- Minimum tap-target size, screen-reader labels on every candidate card, high-contrast mode, and font-scaling support — targeting WCAG 2.1 AA (NFR in `05-Product-Requirements.md` §5.5).
- Symbol + photo combination (not text-only) supports voters with limited literacy — a common and important requirement for cooperative/union elections in Nepal.

## 16.6 Preview Mode

- Election Officer can preview the exact ballot a voter will see (per language, per eligible-position combination) before publishing — catches configuration mistakes (wrong candidate order, missing translations) before the nomination window even opens.

## 16.7 Ballot Versioning

- If a candidate is approved *after* an Election Officer has already previewed/tested the ballot, the ballot is **not** frozen — it re-renders live from approved-candidate state at each voter's session. A `ballot_snapshot_hash` is still recorded against each election's final locked candidate list at voting-open time, so post-hoc disputes about "who was on the ballot" can be verified against an immutable record even though rendering itself is dynamic.

Continue to `17-Vote-Counting-Results.md`.
