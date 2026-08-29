# Friends Game Hub Flutter — F12 to F15

## F12 — Match Result + Settlement UX

Implemented a result screen backed by `GET /matches/:id` rather than optimistic client balances. It distinguishes the authoritative game result from financial settlement:

- `FINISHING` / settlement absent → result confirmed, prize processing.
- `FINISHED` + settlement → pot, fee and payout shown from PostgreSQL-backed data.
- Wallet and match history providers are refreshed after settlement completes.
- The live Ludo screen exposes `View result & settlement` only after the authoritative runtime reports `match:finished`.

There is no client-side winner payout calculation used as financial truth.

## F13 — History + Replay + Notifications

Implemented:

- `GET /matches/me` history with cursor pagination.
- Player-specific win/result interpretation.
- `GET /matches/:id` details and settlement information.
- `GET /matches/:id/replay` event timeline.
- `GET /notifications`, mark one read, mark all read.
- Notification unread badge in the main navigation.

Replay intentionally starts as a durable event timeline. A cinematic board replay is deferred until the product actually needs it.

## F14 — Profile + Preferences + Resilience

Implemented:

- Profile from authenticated backend identity.
- Light / Dark / System appearance.
- Game-sound preference.
- Haptics preference.
- Preferences persisted only in SharedPreferences.
- Auth secrets remain in secure storage.
- Existing REST controllers preserve previously loaded data during refresh failures where appropriate.
- Active Ludo reconnect/recovery continues to use server snapshots rather than local game persistence.

No offline game database was added. Friends Ludo is an online authoritative game; fake offline gameplay would be incorrect.

## F15 — End-to-End Integration QA + Release Readiness

Added contract/parser tests and a release checklist covering:

- auth/session restore
- wallet and payments
- matchmaking and escrow
- Socket.IO commands and authoritative events
- duplicate command retry
- version gaps
- reconnect / app resume
- timeout behavior
- no-show refund
- settlement
- match history / replay
- notifications
- theme/preferences
- Android/iOS release configuration

Production hardening such as Firebase Crashlytics or push notifications remains optional and should be added only when required.
