# 23. Web Portal

## 23.1 Purpose & Scope

Admin-heavy workflows (org setup, election configuration, candidate review, reporting) are better suited to a wider screen than a phone. The web portal is the same Flutter codebase (§22.1) compiled for web, with desktop-optimized layouts for admin-role screens — not a separate frontend project.

## 23.2 Portal Surfaces by Role

| Portal | Primary Users | Key Capability |
|---|---|---|
| **Organization Admin Console** | Org Admin | Full org configuration, member management, election creation, billing |
| **Election Officer Console** | Election Officer | Candidate review, live election monitoring, results/recount actions |
| **Auditor Console** | Auditor | Read-only audit log, independent verification tools, recount requests |
| **Observer View** | Observer | Read-only live dashboards, published reports |
| **Super Admin Console** | Super Admin | Cross-org platform management (§23.3) |

## 23.3 Super Admin Console (Platform-Level)

- Organization list, status (trial/active/suspended), plan, health indicators.
- Platform-wide analytics (aggregate only — §18.6).
- Support tools: impersonate-as-Org-Admin (read-only, fully audit-logged, time-boxed session) for support troubleshooting — never used to see individual vote content, which remains inaccessible even to Super Admin outside the logged emergency-override path.
- Subscription/plan management, manual billing adjustments (logged).
- System health: Celery queue depth, notification delivery success rate, DB connection pool status.

## 23.4 Organization Admin Console — Key Views

- **Setup checklist** (first-run experience, §11.5).
- **Member table**: filterable, sortable, bulk actions (message, suspend, export).
- **Election board**: kanban-style view by state (Draft / Nomination Open / Voting Open / Closed), matching the state machine in §13.5.
- **Billing**: current plan, usage against plan limits, invoice history, upgrade flow.
- **Settings**: org profile, branding, retention policy, election defaults (§11.7).

## 23.5 Election Officer Console — Key Views

- **Nomination review queue**: pending nominations with document preview, approve/reject inline.
- **Live election monitor**: real-time turnout gauge, votes-cast trend chart, remaining-voter list (for targeted reminder sends).
- **Results & recount**: post-close tally view, recount trigger, certificate download.

## 23.6 Responsive Design Approach

- Desktop-first layouts for admin/officer/auditor consoles (data tables, multi-column dashboards); the same routes render a simplified, stacked mobile layout for admins who occasionally need to act from a phone (e.g., approving an urgent nomination on the go) — reuses the responsive-breakpoint patterns already established in prior Flutter web work rather than building parallel mobile/desktop admin UIs.

## 23.7 Web-Specific Considerations

- Browser tab title/favicon reflect org branding once logged in (multi-tenant white-label cue).
- CSV/Excel export downloads trigger native browser download (not app-only share sheet).
- No browser localStorage/sessionStorage use for anything session- or vote-sensitive — tokens held in memory with silent-refresh, consistent with the security posture in `09-Authentication-Security.md`.

Continue to `24-AI-Features.md`.
