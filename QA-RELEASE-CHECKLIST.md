# Friends Game Hub Flutter — F15 QA & Release Checklist

Run before connecting real-money production traffic.

## Static checks

- [ ] `flutter pub get`
- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] Android debug build succeeds.
- [ ] iOS debug build succeeds on macOS if iOS is targeted.

## Authentication

- [ ] Register creates session and wallet.
- [ ] Login works with canonical Ethiopian phone formats accepted by backend.
- [ ] App restart restores session.
- [ ] Concurrent 401s trigger only one refresh flow.
- [ ] Logout clears secure tokens.
- [ ] Blocked account cannot continue authenticated operations.

## Wallet / payments

- [ ] Available and locked balances match backend.
- [ ] Deposit remains pending until admin approval.
- [ ] Withdrawal immediately reflects backend locked funds.
- [ ] Rejected withdrawal restores backend balance after refresh.
- [ ] No screen locally invents a financial balance.

## Matchmaking / entry

- [ ] Insufficient balance is rejected.
- [ ] Queue join/cancel works.
- [ ] Reconnect recovers matchmaking assignment.
- [ ] Both players show locked entry funds after match creation.
- [ ] No-show cancellation returns funds.

## Ludo realtime

- [ ] Both users join the match room.
- [ ] Starting roll comes only from server.
- [ ] Roll uses `commandId + expectedVersion`.
- [ ] Move sends token ID only.
- [ ] Same command retry does not double execute.
- [ ] Stale expected version causes recovery rather than local mutation.
- [ ] Legal tokens match authoritative server state.
- [ ] Dice animation ends on server dice value.
- [ ] Token animation never blocks server state processing.

## Reconnect / timeout

- [ ] Temporary socket loss keeps board visible.
- [ ] Reconnect rejoins room and syncs authoritative snapshot.
- [ ] App background/resume recovers active match.
- [ ] Flutter timer reaching zero does not advance turn locally.
- [ ] Roll timeout is server-driven.
- [ ] Move timeout is server-driven.
- [ ] Disconnect grace and authoritative resign work.

## Result / settlement

- [ ] `match:finished` produces final runtime result.
- [ ] Result screen can show settlement processing.
- [ ] Final settlement displays pot/fee/payout from backend.
- [ ] Wallet refresh happens after settlement.
- [ ] No client payout calculation changes balance.

## History / notifications

- [ ] History pagination works.
- [ ] A player cannot open another player's match.
- [ ] Match details show correct participants and settlement.
- [ ] Replay timeline loads durable events.
- [ ] Notifications load.
- [ ] Mark-one-read works.
- [ ] Mark-all-read works.
- [ ] Main navigation unread badge updates.

## UX / devices

- [ ] Light theme checked.
- [ ] Dark theme checked.
- [ ] System theme checked.
- [ ] Small Android phone checked.
- [ ] Typical Android phone checked.
- [ ] Large phone checked.
- [ ] Text scale/accessibility checked.
- [ ] Slow network checked.
- [ ] No-network states checked.
- [ ] App does not expose raw backend exceptions.

## Release environment

- [ ] Production API URL supplied with `--dart-define`.
- [ ] Production Socket URL supplied with `--dart-define`.
- [ ] HTTPS/WSS used in production.
- [ ] Android cleartext traffic is not required in production.
- [ ] Release signing configured outside source control.
- [ ] Secrets are not stored in Dart source.
- [ ] Backend B0-B20 migrations deployed.
- [ ] Backend health reports PostgreSQL + Redis healthy.
