# F4–F7 Implementation Notes

## F4 — Game Hub + Ludo Lobby

The client reads the backend game catalog and Ludo modes instead of defining stake rooms in UI code. `GameMode` keeps the backend `stakeAmountMinor`, `platformFeeBps`, `turnDurationSeconds` and `rulesVersion` values.

Estimated payout shown in the lobby is display-only. B16 remains the financial settlement authority.

## F5 — Matchmaking

One Riverpod controller owns the queue state. It uses the backend Socket.IO acknowledgement contract and the private `matchmaking:matched` event. On entry it checks `matchmaking:status` first so temporary disconnects do not create a second search.

The client never creates matches or reserves stake itself.

## F6 — Socket.IO

`GameSocketService` is global and authenticated. It is deliberately transport-focused: connection, acknowledgement requests and event forwarding. It does not own Ludo game state.

## F7 — Board

Static geometry uses `CustomPainter`; tokens are positioned widgets. This keeps the board efficient while preserving tap semantics and future token animations.

The track and safe-square constants mirror backend `LUDO_CLASSIC_V1`. This is visual coordinate mapping, not duplicated move validation.

## Deferred intentionally

- no `match:join` from the F7 demo match screen
- no authoritative Ludo snapshot controller yet
- no roll/move commands yet
- no timer authority in Flutter
- no game-state persistence in SharedPreferences
- no local move legality engine
- no token animation queue yet

Those belong to F8–F11.

> F8-F11 update: the former F7 demo match screen has been replaced by the live authoritative `LudoMatchScreen`. The board painter/geometry remain the F7 rendering foundation.
