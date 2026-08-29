# Friends Game Hub Flutter — F0 to F15

Player application for the Friends Game Hub backend. Ludo is the first implemented game.

## Included

- F0 Foundation / design system
- F1 Authentication / secure session
- F2 App shell / wallet
- F3 Deposit / withdrawal
- F4 Game Hub / Ludo lobby
- F5 Matchmaking
- F6 Socket.IO foundation
- F7 Ludo board rendering
- F8 Authoritative Ludo state binding
- F9 Roll / move commands
- F10 Presentation animations
- F11 Timer / reconnect / recovery
- F12 Result / settlement UX
- F13 History / replay / notifications
- F14 Profile / preferences / resilience
- F15 QA / release-readiness contract

## Run

```bash
flutter pub get
flutter analyze
flutter test
```

Android emulator:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:5000/api \
  --dart-define=SOCKET_BASE_URL=http://10.0.2.2:5000
```

Physical device on the same network:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://YOUR_SERVER_IP:5000/api \
  --dart-define=SOCKET_BASE_URL=http://YOUR_SERVER_IP:5000
```

Production must use HTTPS/WSS endpoints.

## Core authority rule

Flutter sends intent and renders authoritative server state. It does not decide dice, legal movement, turn expiry, winner, escrow or settlement.

## Release gate

See `QA-RELEASE-CHECKLIST.md` before a controlled paid launch.
