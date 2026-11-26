import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/app/router.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/core/widgets/ui.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';
import 'package:friends_game_app/features/game_hub/domain/game_routes.dart';
import 'package:friends_game_app/features/game_hub/presentation/controllers/game_hub_controller.dart';
import 'package:friends_game_app/features/live_lobby/domain/lobby_challenge.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/goal_picker.dart';
import 'package:friends_game_app/features/match/presentation/widgets/crown_icon.dart';
import 'package:friends_game_app/features/requests/request_center.dart';

/// Shows the open game request over whatever screen is up, and opens the
/// match once a request is accepted. Sits once above the app's navigator.
class RequestSheetHost extends ConsumerStatefulWidget {
  const RequestSheetHost({super.key, required this.child, this.blocked = false});
  final Widget child;
  final bool blocked;

  @override
  ConsumerState<RequestSheetHost> createState() => _RequestSheetHostState();
}

class _RequestSheetHostState extends ConsumerState<RequestSheetHost> {
  String? _shownId;
  ModalBottomSheetRoute<void>? _requestRoute;

  BuildContext? get _navigatorContext => ref.read(routerProvider).routerDelegate.navigatorKey.currentContext;

  String get _location => ref.read(routerProvider).routerDelegate.currentConfiguration.uri.path;

  void _onChange(RequestCenterState? previous, RequestCenterState next) {
    if (widget.blocked) return;
    final request = next.request;
    if (request != null && request.id != _shownId) _show(request);
    if (request == null && _shownId != null) _close();

    final open = next.openMatch;
    if (open != null) {
      final code = open.gameCode ?? _gameCodeOf(previous?.request) ?? GameCodes.ludo;
      final target = GameRoutes.match(code, open.matchId);
      if (_location != target) ref.read(routerProvider).go(target);
      HapticFeedback.mediumImpact();
    }
    final notice = next.notice;
    final context = _navigatorContext;
    if (notice != null && context != null) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(notice)));
    }
    if (open != null || notice != null) ref.read(requestCenterProvider.notifier).consumed();
  }

  String? _gameCodeOf(LobbyChallenge? request) =>
      request == null ? null : _stakeOf(ref, request.gameModeId)?.gameCode;

  void _show(LobbyChallenge request) {
    // A rematch for the match on screen is answered on the result screen itself.
    if (request.isRematch && request.sourceMatchId != null && _location.endsWith('/result/${request.sourceMatchId}')) return;
    final context = _navigatorContext;
    if (context == null) return;
    if (_shownId != null) _close();
    _shownId = request.id;
    if (request.opponentId == ref.read(authControllerProvider).user?.id) HapticFeedback.heavyImpact();
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = ModalBottomSheetRoute<void>(
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      capturedThemes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: const SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20), child: _RequestSheet(),
        ),
      ),
    );
    _requestRoute = route;
    navigator.push(route).whenComplete(() {
      if (_requestRoute == route) {
        _requestRoute = null;
        _shownId = null;
      }
    });
  }

  void _close() {
    final route = _requestRoute;
    _shownId = null;
    _requestRoute = null;
    if (route?.isActive == true) route!.navigator?.removeRoute(route);
  }

  @override
  void didUpdateWidget(covariant RequestSheetHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blocked == widget.blocked) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.blocked) {
        _close();
      } else {
        _onChange(null, ref.read(requestCenterProvider));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(requestCenterProvider, _onChange);
    return widget.child;
  }
}

GameMode? _stakeOf(WidgetRef ref, String stakeId) {
  for (final modes in ref.read(gameHubControllerProvider).modesByGame.values) {
    for (final mode in modes) {
      if (mode.id == stakeId) return mode;
    }
  }
  return null;
}

class _RequestSheet extends ConsumerWidget {
  const _RequestSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(requestCenterProvider);
    final center = ref.read(requestCenterProvider.notifier);
    final request = state.request;
    if (request == null) return const SizedBox(height: 120);

    final me = ref.watch(authControllerProvider.select((auth) => auth.user?.id));
    final incoming = request.opponentId == me;
    final other = (incoming ? request.challengerName : request.opponentName) ?? 'Player';
    final stake = _stakeOf(ref, request.gameModeId);
    final game = GameRoutes.displayName(stake?.gameCode ?? GameCodes.ludo);
    final theme = Theme.of(context);
    final total = request.expiresAt.difference(request.createdAt);

    final title = incoming
        ? (request.isRematch ? '$other wants a rematch' : '$other wants to play')
        : 'Waiting for $other';
    final subtitle = incoming ? 'Accept to start the match now.' : 'They have a moment to answer.';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 4),
      Center(
        child: Stack(alignment: Alignment.center, children: [
          CountdownRing(expiresAt: request.expiresAt, total: total, size: 92),
          PlayerAvatar(name: other, size: 70),
        ]),
      ),
      const SizedBox(height: 16),
      Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(subtitle, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
      const SizedBox(height: 20),
      _Terms(game: game, stake: stake, tokensToWin: stake?.gameCode == GameCodes.ludo ? request.tokensToWin : null),
      if (state.error != null) ...[
        const SizedBox(height: 12),
        Text(state.error!, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
      ],
      const SizedBox(height: 20),
      if (incoming)
        Row(children: [
          Expanded(
            child: OutlinedButton(onPressed: state.busy ? null : center.decline, child: const Text('Decline')),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: state.busy ? null : center.accept,
              child: state.busy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                  : const Text('Accept and play'),
            ),
          ),
        ])
      else
        OutlinedButton(
          onPressed: state.busy ? null : center.cancel,
          child: Text(state.busy ? 'Cancelling…' : 'Cancel request'),
        ),
    ]);
  }
}

/// What the match is played for: game, stake, prize and (Ludo) goal.
class _Terms extends StatelessWidget {
  const _Terms({required this.game, required this.stake, this.tokensToWin});
  final String game;
  final GameMode? stake;
  final int? tokensToWin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    Widget row(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
            value,
          ]),
        );
    final bold = theme.textTheme.titleSmall;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(color: palette.surfaceAlt, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        row('Game', Text(game, style: bold)),
        if (stake != null) ...[
          row('Your stake', StakePill(amountMinor: stake!.stakeAmountMinor)),
          row(
            'Winner gets',
            Text(
              MoneyFormatter.compactEtb(stake!.estimatedWinnerPayoutMinor),
              style: bold?.copyWith(color: palette.money, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ],
        if (tokensToWin != null)
          row(
            'Goal',
            Row(mainAxisSize: MainAxisSize.min, children: [
              CrownRow(count: tokensToWin!, size: 16),
              const SizedBox(width: 6),
              Text(goalLabel(tokensToWin!), style: bold),
            ]),
          ),
      ]),
    );
  }
}
