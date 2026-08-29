# Friends Game Hub Flutter Architecture — F0 to F11

## Ownership

```text
REST durable state
  AuthController / WalletController / PaymentController

Realtime game state
  GameSocketService -> LudoMatchController

Presentation state
  LudoAnimationQueueController / Theme preferences / local UI state
```

The backend remains authoritative for dice, legal moves, token positions, turn phase, timeout, winner and settlement.

## Realtime path

```text
User tap
  -> LudoMatchController creates commandId + expectedVersion
  -> Socket.IO ACK
  -> ACK only confirms acceptance/dedupe
  -> backend emits versioned event(s)
  -> central event reducer mutates authoritative Flutter snapshot
  -> presentation queue animates what already happened
```

## Same-version event batches

B9 increments the game version once per command, then can emit several facts carrying the same version. Flutter therefore does not use the incorrect rule "same version always duplicate". It tracks an open event batch and event IDs.

## Recovery path

```text
socket reconnect / app resume / version gap / manual recovery
  -> match:join
  -> ludo:sync
  -> replace snapshot
  -> close event batch
```

No periodic canonical sync and no sync after every normal server event.

## Board

`CustomPainter` renders the static 15x15 board. Tokens remain interactive widgets in a `Stack`. F10 adds a presentation-only moving-token overlay; the authoritative token state still updates immediately.


## F12-F15 boundaries

- Result UI reads durable match/settlement data; it never credits a wallet locally.
- History and replay read B17 PostgreSQL data. Replay is an event timeline in V1.
- Notification unread state has one Riverpod owner and uses B18 APIs.
- Theme/sound/haptics are local preferences only.
- No local Ludo snapshot is used as recovery truth; reconnect continues to use B11/B14 server sync.
- F15 freezes the client integration contract before production-only observability/push additions.
