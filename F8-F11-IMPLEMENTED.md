# Friends Game Hub Flutter — F8 to F11

## F8 — Authoritative Ludo State Binding

- `match:join` replaces the F7 demo board with the backend B9 runtime snapshot.
- Flutter models mirror `LudoMatchRuntimeState`, `LudoGameState`, starting-roll state, token state and B14 timing state.
- `LudoMatchController` is the single owner of active match state.
- Socket events are applied through one reducer; widgets never register game listeners.
- `eventId` dedupes repeated transport delivery.
- Version handling supports the backend's important detail that one command may emit **multiple events with the same version**.
  - next version: open/apply that event batch;
  - same version: accepted only while that batch is open;
  - older version: ignored;
  - version gap: `match:join` + `ludo:sync` recovery.
- A snapshot closes the current event batch so delayed events at the snapshot version cannot overwrite recovered state.

## F9 — Roll + Move Commands

Commands carry only intent:

```text
matchId
commandId
expectedVersion
[tokenId]
```

Flutter never sends dice, destination, capture or winner data.

- `ludo:roll_for_start`
- `ludo:roll`
- `ludo:move`
- `ludo:resign`

ACK and EVENT are separate:

```text
ACK   -> accepted / duplicate / error, stop retrying
EVENT -> authoritative state mutation
```

If an ACK times out, Flutter retries the **same commandId once** so backend Redis command dedupe remains effective.

Legal token highlighting is driven only by `game.legalTokenIds` from the authoritative state.

## F10 — Presentation Animation Queue

Authoritative state updates immediately. Visual effects are queued independently:

- server dice animation ending on the server value;
- step-wise token movement overlay from `tokenBefore` to `tokenAfter`;
- capture emphasis at the returned base token;
- token-finish, turn, extra-roll and match-finish presentation events.

The animation queue never blocks the backend and never becomes game truth.

## F11 — Timer + Reconnect + Recovery

- `turnEndsAt` from `match:join` / `ludo:sync` is treated as authoritative.
- Socket envelope `serverTime` is used to maintain a client/server clock offset.
- Flutter reaching zero performs **no lifecycle action**; backend B14 remains the timeout authority.
- During disconnect, the board remains visible and a reconnect banner is shown.
- Socket reconnect: rejoin room, then sync snapshot.
- App resume: rejoin room, then sync snapshot.
- Version gap: rejoin room, then sync snapshot.
- Manual Sync is recovery only, not the normal gameplay path.

### Current B20 timing-contract note

The B20 backend stores a new exact `turnEndsAt` after a gameplay transition, but its normal Ludo event envelope does not currently include that new timing object. Therefore this client:

1. uses the exact backend deadline returned by `match:join` / `ludo:sync`;
2. after a normal phase-changing event, displays a **non-authoritative estimated countdown** (`~`) based on the event's server timestamp plus the match mode's `turnDurationSeconds`;
3. never uses that estimate to trigger a move, roll, timeout, resignation or turn transition.

This avoids the old anti-pattern of calling canonical sync after every socket event. A future backend protocol revision can emit `ludo:timing` after B14 schedules the deadline; Flutter can then replace the display estimate with the exact new deadline without changing game-state ownership.
