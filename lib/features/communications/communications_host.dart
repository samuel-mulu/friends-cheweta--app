import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/app/router.dart';
import 'package:friends_game_app/core/errors/app_failure.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/communications/communications_controllers.dart';
import 'package:friends_game_app/features/communications/communications_repository.dart';
import 'package:friends_game_app/features/requests/request_sheet.dart';

class CommunicationsHost extends ConsumerStatefulWidget {
  const CommunicationsHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CommunicationsHost> createState() => _CommunicationsHostState();
}

class _CommunicationsHostState extends ConsumerState<CommunicationsHost>
    with WidgetsBindingObserver {
  late final GoRouter _router;
  StreamSubscription<RealtimeEvent>? _socketEvents;
  DialogRoute<void>? _forcedRoute;
  OverlayEntry? _bannerEntry;
  BroadcastNotice? _shownBanner;
  Timer? _recheck;
  bool _foreground = true;
  String _path = '';

  @override
  void initState() {
    super.initState();
    _router = ref.read(routerProvider);
    _path = _currentPath();
    _router.routerDelegate.addListener(_routeChanged);
    _socketEvents =
        ref.read(gameSocketServiceProvider).events.listen(_onSocket);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _recheck?.cancel();
    _socketEvents?.cancel();
    _removeBanner();
    _router.routerDelegate.removeListener(_routeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _refresh();
    } else if (ref.read(communicationsPlayerProvider) != null) {
      ref.read(broadcastControllerProvider.notifier).hideBanner();
    }
  }

  String _currentPath() => _router.routerDelegate.currentConfiguration.isEmpty
      ? ''
      : _router.state.uri.path;

  void _routeChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final next = _currentPath();
      if (next == _path) return;
      setState(() => _path = next);
      if (ref.read(broadcastControllerProvider).inbox?.forced != null) {
        unawaited(ref.read(broadcastControllerProvider.notifier).refresh());
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _refresh() {
    if (ref.read(communicationsPlayerProvider) == null) return;
    unawaited(ref.read(broadcastControllerProvider.notifier).refresh());
    unawaited(ref.read(feedbackControllerProvider.notifier).refresh());
  }

  void _onSocket(RealtimeEvent event) {
    if (!mounted || ref.read(communicationsPlayerProvider) == null) return;
    switch (event.name) {
      case 'session:ready':
        _refresh();
      case 'broadcast:changed':
        final data = event.data;
        final kind = data['kind'];
        final id = data['id'];
        final revision = data['revision'];
        final spotlight = _foreground &&
                !_isMatchRoute &&
                (kind == 'PUBLISHED' || kind == 'REMINDED') &&
                id is String &&
                revision is int
            ? (id: id, revision: revision)
            : null;
        unawaited(ref
            .read(broadcastControllerProvider.notifier)
            .refresh(spotlight: spotlight));
      case 'feedback:changed':
        unawaited(ref.read(feedbackControllerProvider.notifier).refresh());
      case 'match:ready':
      case 'match:finished':
      case 'match:cancelled':
        if (ref.read(broadcastControllerProvider).inbox?.forced != null) {
          unawaited(ref.read(broadcastControllerProvider.notifier).refresh());
        }
    }
  }

  bool get _isMatchRoute =>
      RegExp(r'^/(ludo|dama|karta)/match/[^/]+$').hasMatch(_currentPath());

  bool _blocking(BroadcastInbox? inbox) =>
      inbox?.forced != null && _currentPath() != inbox?.matchPath;

  void _reconcileOverlays() {
    if (!mounted) return;
    final state = ref.read(broadcastControllerProvider);
    final inbox = state.inbox;
    _reconcileBanner(
        inbox?.forced == null && !_isMatchRoute ? state.banner : null);
    if (inbox?.forced != null) {
      _recheck ??= Timer.periodic(const Duration(seconds: 8), (_) {
        if (mounted && _foreground) {
          unawaited(ref.read(broadcastControllerProvider.notifier).refresh());
        }
      });
    } else {
      _recheck?.cancel();
      _recheck = null;
    }
    if (!_blocking(inbox)) {
      final route = _forcedRoute;
      _forcedRoute = null;
      if (route?.isActive == true) route!.navigator?.removeRoute(route);
      return;
    }
    if (_forcedRoute?.isActive == true) return;
    final navigator = _router.routerDelegate.navigatorKey.currentState;
    if (navigator == null || !navigator.mounted) return;
    final route = DialogRoute<void>(
      context: navigator.context,
      barrierDismissible: false,
      requestFocus: true,
      builder: (_) => _ForcedNoticeDialog(onResume: (path) {
        if (path == ref.read(broadcastControllerProvider).inbox?.matchPath) {
          _router.go(path);
        }
      }),
    );
    _forcedRoute = route;
    unawaited(navigator.push(route).whenComplete(() {
      if (!mounted || _forcedRoute != route) return;
      _forcedRoute = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reconcileOverlays());
      WidgetsBinding.instance.ensureVisualUpdate();
    }));
  }

  void _removeBanner() {
    _bannerEntry?.remove();
    _bannerEntry?.dispose();
    _bannerEntry = null;
    _shownBanner = null;
  }

  void _reconcileBanner(BroadcastNotice? banner) {
    if (banner == _shownBanner) return;
    _removeBanner();
    final overlay = _router.routerDelegate.navigatorKey.currentState?.overlay;
    if (banner == null || overlay == null) return;
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        left: 12,
        right: 12,
        top: MediaQuery.paddingOf(context).top + kToolbarHeight + 4,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: _BroadcastBanner(
              notice: banner,
              onOpen: () {
                ref.read(broadcastControllerProvider.notifier).hideBanner();
                if (_currentPath() != '/messages') _router.push('/messages');
              },
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    _bannerEntry = entry;
    _shownBanner = banner;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(broadcastControllerProvider);
    ref.watch(feedbackControllerProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reconcileOverlays());
    return RequestSheetHost(
        blocked: _blocking(state.inbox), child: widget.child);
  }
}

class _ForcedNoticeDialog extends ConsumerWidget {
  const _ForcedNoticeDialog({required this.onResume});
  final ValueChanged<String> onResume;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(broadcastControllerProvider);
    final notice = state.inbox?.forced;
    final matchPath = state.inbox?.matchPath;
    if (notice == null) return const SizedBox.shrink();
    return PopScope(
      canPop: false,
      child: AlertDialog(
        scrollable: true,
        icon: const Icon(Icons.campaign_rounded),
        title: Text(notice.title),
        content: SelectableText(notice.body),
        actions: [
          if (state.error != null)
            TextButton(
              onPressed: ref.read(broadcastControllerProvider.notifier).refresh,
              child: const Text('Retry connection'),
            ),
          if (matchPath != null)
            FilledButton(
              onPressed: () => onResume(matchPath),
              child: const Text('Resume match'),
            ),
        ],
      ),
    );
  }
}

class _BroadcastBanner extends ConsumerWidget {
  const _BroadcastBanner({required this.notice, required this.onOpen});
  final BroadcastNotice notice;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.primaryContainer,
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      child: Row(children: [
        Expanded(
            child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(Icons.campaign_outlined, color: colors.onPrimaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notice.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      notice.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onPrimaryContainer,
                          ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        )),
        IconButton(
          tooltip: notice.canDismiss ? 'Dismiss announcement' : 'Close banner',
          icon: Icon(Icons.close_rounded, color: colors.onPrimaryContainer),
          onPressed: () async {
            final controller = ref.read(broadcastControllerProvider.notifier);
            final messenger = ScaffoldMessenger.maybeOf(context);
            controller.hideBanner();
            if (!notice.canDismiss) return;
            try {
              await controller.dismiss(notice);
            } on AppFailure catch (error) {
              if (messenger?.mounted == true) {
                messenger!.showSnackBar(SnackBar(content: Text(error.message)));
              }
            }
          },
        ),
      ]),
    );
  }
}
