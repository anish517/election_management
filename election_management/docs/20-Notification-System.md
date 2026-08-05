# 20. Notification System

## 20.1 Channels

| Channel | Provider | Use |
|---|---|---|
| Push | Firebase Cloud Messaging (FCM) | Primary channel for app-active users |
| SMS | Sparrow SMS (Nepal), Twilio (international fallback) | OTP, critical reminders — highest deliverability for non-smartphone-app users |
| Email | SMTP/SendGrid | Formal notices (nomination decisions, result certificates), less time-sensitive |
| WhatsApp | (v1.1+, via WhatsApp Business API) | Optional, high-engagement channel for orgs whose members are WhatsApp-heavy |

## 20.2 Notification Triggers

| Event | Recipient | Channel(s) |
|---|---|---|
| Member invited | Member | Email + SMS |
| Nomination window opens | Eligible members | Push + Email |
| Nomination submitted | Election Officer | Push + Email |
| Nomination approved/rejected | Candidate | Push + SMS + Email |
| Voting opens | Eligible voters | Push + SMS + Email |
| Voting closing soon (24h, 2h reminders) | Voters who haven't voted | Push + SMS |
| Vote cast (confirmation + receipt) | Voter | Push + Email |
| Results provisional | Org Admin, Election Officer | Push + Email |
| Results final | All eligible voters (+ public, if visibility allows) | Push + Email |
| Contest filed | Org Admin | Push + Email (high priority) |
| Subscription payment due/failed | Org Admin | Email + SMS |

## 20.3 Templates

- Every notification type has a versioned template keyed by `template_key` (see `08-Database-Design.md` `notifications` table), stored bilingually (Nepali/English), with variable interpolation (`{{member_name}}`, `{{election_title}}`, `{{voting_closes_bs_date}}`).
- BS dates are rendered in templates via the shared BS-calendar utility, never hand-formatted per template, to avoid the mismatch bugs seen in earlier calendar work.

## 20.4 Delivery & Retry

- Notifications are dispatched via the `send_notification` Celery task (async, never blocking the triggering request).
- Failed sends retry with exponential backoff (3 attempts) before marking `status = failed` and surfacing in an Org Admin-visible delivery-failure log (useful for catching bad phone/email data early).
- SMS and push are treated as **best-effort, not guaranteed** — critical actions (e.g., "voting closes in 2 hours") always also queue an email as a fallback channel.

## 20.5 User Preferences

- Members can opt out of non-critical notification types (e.g., general announcements) but **cannot** opt out of election-critical notices (nomination decision, voting window, results) — these are treated as essential service communications, not marketing.

## 20.6 Rate & Cost Control

- SMS is the most expensive channel; the system batches non-urgent SMS (e.g., digest-style "3 elections need your attention") where possible rather than sending one SMS per event, and always prefers push for members with an active app session.

Continue to `21-REST-API-Documentation.md`.
