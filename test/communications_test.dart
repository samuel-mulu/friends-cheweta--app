import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/app/router.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/communications/communications_controllers.dart';
import 'package:friends_game_app/features/communications/communications_host.dart';
import 'package:friends_game_app/features/communications/communications_repository.dart';
import 'package:friends_game_app/features/communications/messages_screen.dart';
import 'package:go_router/go_router.dart';

import 'support/fake_socket.dart';
import 'support/fake_communications.dart';

const liveMatch = '/ludo/match/live-match';
final _date = DateTime.utc(2026, 11, 24);
const _snapshot = '1';

BroadcastNotice _notice(String title, BroadcastMode mode, {int revision = 1}) =>
    BroadcastNotice(
      id: title,
      title: title,
      body: 'Please read this announcement.',
      mode: mode,
      revision: revision,
      createdAt: _date,
    );

class _Communications extends EmptyCommunications {
  final items = <BroadcastNotice>[];
  final dismissed = <BroadcastNotice>[];
  final seen = <String>[];
  final sent = <(FeedbackCategory, String)>[];
  BroadcastNotice? force;
  String? matchPath;
  PlayerFeedback? reply;
  Completer<void>? sendDelay;

  @override
  Future<BroadcastInbox> broadcasts(
          {int page = 1, String? spotlightId}) async =>
      BroadcastInbox(
        items: List.of(items),
        unreadCount: items.where((item) => item.canDismiss).length,
        hasMore: false,
        forced: force,
        matchPath: matchPath,
        spotlight: items.where((item) => item.id == spotlightId).firstOrNull,
      );

  @override
  Future<void> dismiss(BroadcastNotice notice) async {
    dismissed.add(notice);
    items.removeWhere((item) => item.id == notice.id);
  }

  @override
  Future<FeedbackInbox> feedback({int page = 1}) async => FeedbackInbox(
        items: [if (reply != null) reply!],
        unreadCount: reply != null && seen.isEmpty ? 1 : 0,
        hasMore: false,
        seenThrough: _snapshot,
      );

  @override
  Future<void> markSeen(String seenThrough) async => seen.add(seenThrough);

  @override
  Future<void> send(
      FeedbackCategory category, String message, String requestId) async {
    sent.add((category, message));
    await sendDelay?.future;
  }
}

Future<GoRouter> _mount(
  WidgetTester tester,
  _Communications repo,
  FakeSocket socket, {
  String initial = '/home',
  Brightness brightness = Brightness.light,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 720);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(
        path: '/home',
        builder: (_, __) => Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => context.push('/messages'),
                  child: const Text('Open inbox'),
                ),
              ),
            )),
    GoRoute(path: '/messages', builder: (_, __) => const MessagesScreen()),
    GoRoute(
        path: '/ludo/match/:id',
        builder: (_, __) => const Scaffold(body: Text('Current match board'))),
    GoRoute(
        path: '/chats',
        builder: (_, __) => const Scaffold(body: Text('Chat list'))),
  ]);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    await socket.events$.close();
    await socket.statuses$.close();
  });
  await tester.pumpWidget(ProviderScope(
    overrides: [
      routerProvider.overrideWithValue(router),
      authControllerProvider.overrideWith(SignedInAs.new),
      gameSocketServiceProvider.overrideWithValue(socket),
      communicationsRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp.router(
      theme: ThemeData(brightness: brightness),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.3)),
        child: CommunicationsHost(child: child!),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return router;
}

void _broadcast(FakeSocket socket, BroadcastNotice item, String kind) {
  socket.push('broadcast:changed', {
    'id': item.id,
    'revision': item.revision,
    'kind': kind,
  });
}

void main() {
  testWidgets(
      'forced notices wait for a matching live game and allow only resuming it',
      (tester) async {
    final socket = FakeSocket();
    final force = _notice('Service notice', BroadcastMode.forced);
    final repo = _Communications()..matchPath = liveMatch;
    final router = await _mount(tester, repo, socket,
        initial: liveMatch, brightness: Brightness.dark);

    repo.force = force;
    _broadcast(socket, force, 'FORCED_CHANGED');
    await tester.pumpAndSettle();
    expect(find.text('Current match board'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    router.go('/home');
    await tester.pumpAndSettle();
    expect(find.text('Service notice'), findsOneWidget);
    expect(find.text('Resume match'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('Resume match'));
    await tester.pumpAndSettle();
    expect(find.text('Current match board'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    repo.matchPath = null;
    socket.push('match:finished', {});
    await tester.pumpAndSettle();
    expect(find.text('Service notice'), findsOneWidget);
    expect(find.text('Resume match'), findsNothing);
    repo.force = null;
    _broadcast(socket, force, 'DELETED');
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'persistent and dismissible banners use the account inbox correctly',
      (tester) async {
    final socket = FakeSocket();
    final repo = _Communications();
    await _mount(tester, repo, socket);
    final pinned = _notice('Pinned notice', BroadcastMode.persistent);
    repo.items.add(pinned);
    _broadcast(socket, pinned, 'PUBLISHED');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close banner'));
    await tester.pumpAndSettle();
    expect(repo.dismissed, isEmpty);

    final normal = _notice('Normal notice', BroadcastMode.dismissible);
    repo.items.add(normal);
    _broadcast(socket, normal, 'PUBLISHED');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dismiss announcement'));
    await tester.pumpAndSettle();
    expect(repo.dismissed, [normal]);

    final reminded =
        _notice(normal.title, BroadcastMode.dismissible, revision: 2);
    repo.items.add(reminded);
    _broadcast(socket, reminded, 'REMINDED');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Normal notice'));
    await tester.pumpAndSettle();
    expect(find.text('Pinned notice'), findsOneWidget);
    expect(find.text('Pinned'), findsOneWidget);
    expect(find.text('Normal notice'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
    await tester.ensureVisible(find.text('Dismiss'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dismiss').hitTestable());
    await tester.pumpAndSettle();
    expect(repo.dismissed, [normal, reminded]);
    expect(find.text('Normal notice'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'feedback opens the reply snapshot and preserves a forced dialog during submission',
      (tester) async {
    final socket = FakeSocket();
    final repo = _Communications()
      ..reply = PlayerFeedback(
        id: 'private',
        category: FeedbackCategory.other,
        status: 'Replied',
        createdAt: _date,
        reply: 'A private message from admin',
      )
      ..sendDelay = Completer<void>();
    await _mount(tester, repo, socket, initial: '/messages');
    final context = tester.element(find.byType(MessagesScreen));
    final container = ProviderScope.containerOf(context);
    expect(container.read(communicationsUnreadProvider), 1);
    await tester.tap(find.text('Feedback'));
    await tester.pumpAndSettle();
    expect(repo.seen, [_snapshot]);
    expect(container.read(communicationsUnreadProvider), 0);
    expect(find.text('A private message from admin'), findsOneWidget);
    await tester.tap(find.text('Send feedback'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField), 'Please improve the rules screen.');
    await tester.tap(find.descendant(
        of: find.byType(Form),
        matching: find.widgetWithText(FilledButton, 'Send feedback')));
    await tester.pumpAndSettle();
    expect(repo.sent,
        [(FeedbackCategory.feedback, 'Please improve the rules screen.')]);

    final force = _notice('A forced notice', BroadcastMode.forced);
    repo.force = force;
    _broadcast(socket, force, 'FORCED_CHANGED');
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    repo.sendDelay!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    repo.force = null;
    socket.push('session:ready', {});
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.text('Player chat'));
    await tester.pumpAndSettle();
    expect(find.text('Chat list'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
