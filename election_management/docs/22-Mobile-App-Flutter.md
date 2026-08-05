# 22. Mobile App (Flutter)

## 22.1 App Strategy

**One Flutter codebase, role-aware navigation** — not three separate apps. A single app serves Voter, Candidate, and (on tablet/web) Election Officer/Org Admin views, gated by the authenticated user's role, consistent with the single-codebase-per-surface pattern already used across prior Flutter projects. Platform targets: Android, iOS, Web (admin-heavy flows favor Web/tablet, voting flows are mobile-first).

## 22.2 State Management

- **Riverpod**, matching the existing stack, using `StateNotifier`/`AsyncNotifier` for auth and election-state providers, consistent with the pattern already proven for phone-OTP auth flows (`AuthGate` routing, `flutter_riverpod` v3-compatible imports).
- Key providers: `authProvider`, `currentOrgProvider`, `electionListProvider`, `ballotProvider(electionId)`, `voteSessionProvider`.

## 22.3 App Structure

```
lib/
├── core/
│   ├── network/          # Dio client, interceptors (JWT refresh, error mapping)
│   ├── theme/             # Org-brand-color-aware theming
│   └── localization/      # ne/en, BS calendar utilities (nepali_utils-based)
├── features/
│   ├── auth/               # login, OTP, 2FA setup
│   ├── organizations/       # org switcher, org profile
│   ├── members/             # (admin) import, list, detail
│   ├── elections/           # list, detail, creation wizard (admin)
│   ├── candidates/          # nomination form, status tracker
│   ├── voting/              # ballot render, vote-session, receipt
│   ├── results/             # results view, certificate download
│   ├── dashboard/           # admin KPI cards, live turnout
│   └── notifications/       # in-app notification center
├── shared/
│   ├── widgets/             # BS date picker, candidate card, timer/countdown
│   └── models/
└── main.dart
```

## 22.4 Key Screens

| Screen | Role | Notes |
|---|---|---|
| Org switcher | All | For users belonging to multiple orgs (§11.6) |
| Election list | Voter/Candidate | Filtered to their eligible/relevant elections, BS-date countdowns |
| Ballot screen | Voter | Renders per voting method (§15) — distinct widget per method, sharing a common `BallotPositionCard` |
| Vote confirmation | Voter | Explicit "confirm your selections" step before final submit — irreversible action (BR-03), so this screen deliberately adds friction |
| Receipt screen | Voter | Shows receipt hash + "what this proves" explainer — trust-building UX, not just a raw hash |
| Nomination form | Candidate | Multi-step, saves draft locally before submit (poor-connectivity resilience) |
| Nomination status tracker | Candidate | Real-time status via polling or push |
| Admin dashboard | Org Admin/Election Officer | BS-date-aware KPI cards, live turnout chart |
| Election creation wizard | Org Admin/Election Officer | Multi-step form, matches §13.2 |
| Member import | Org Admin | CSV upload + validation-result review |
| Audit log viewer | Auditor/Org Admin | Filterable timeline |

## 22.5 Offline & Poor-Connectivity Handling

- Ballot selections held in local state until final submit — a dropped connection *before* submit loses nothing since nothing has been sent yet.
- Submit action retries automatically on network failure (with clear UI feedback: "Reconnecting, your selections are saved..."), never silently fails or double-submits — idempotency enforced via the single-use `voting_session_token` (§21.7): a retried submit with the same token either succeeds once or returns the original result, never creates a second ballot.
- Draft nomination forms persist locally (not just server-side) so a candidate filling a long form on a flaky connection doesn't lose work.

## 22.6 Push Notification Handling

- FCM integration for foreground/background/terminated states — reuses the lock-screen and killed-state notification-reliability patterns already hardened in prior real-time messaging work (background handler ordering, avoiding stale notification display).
- Notification tap deep-links directly to the relevant screen (e.g., tapping "voting closes in 2 hours" opens the ballot screen directly).

## 22.7 Security on Device

- No caching of ballot content or vote selections to disk beyond the active session (in-memory state only, cleared on submit or session expiry).
- Biometric app-lock (device-native, optional) as an additional access gate before opening the app, layered on top of (not replacing) server-side auth.

Continue to `23-Web-Portal.md`.
