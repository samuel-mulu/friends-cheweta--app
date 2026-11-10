import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/theme/app_spacing.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/features/chat/presentation/widgets/chat_thread.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';
import 'package:friends_game_app/features/game_hub/domain/game_routes.dart';
import 'package:friends_game_app/features/live_lobby/domain/lobby_player.dart';
import 'package:friends_game_app/features/live_lobby/presentation/controllers/live_lobby_controller.dart';
import 'package:friends_game_app/features/match/presentation/widgets/crown_icon.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/goal_picker.dart';
import 'package:go_router/go_router.dart';

class LiveLobbyScreen extends ConsumerStatefulWidget {
  const LiveLobbyScreen({super.key, required this.mode});
  final GameMode mode;

  @override
  ConsumerState<LiveLobbyScreen> createState() => _LiveLobbyScreenState();
}

class _LiveLobbyScreenState extends ConsumerState<LiveLobbyScreen> {
  int _tab = 0;

  /// Ludo's "first to N home" goal applies to this room.
  bool get _hasGoal => widget.mode.gameCode == GameCodes.ludo;
  late final LiveLobbyController _lobby;

  @override
  void initState() {
    super.initState();
    _lobby = ref.read(liveLobbyControllerProvider.notifier);
    Future.microtask(() => _lobby.join(widget.mode));
  }

  @override
  void dispose() {
    // Lobby membership lives exactly as long as this screen (also on the way
    // into a match; the server already removed us then, so this is a no-op).
    Future.microtask(_lobby.leave);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(liveLobbyControllerProvider);
    final controller = ref.read(liveLobbyControllerProvider.notifier);
    final socket = ref.watch(gameSocketStatusProvider);
    final challenge = state.activeChallenge;
    final selfId = state.currentUserId;
    final stake =
        MoneyFormatter.minorToEtb(BigInt.from(widget.mode.stakeAmountMinor));
    ref.listen(liveLobbyControllerProvider, (previous, next) {
      final matchId = next.acceptedMatchId;
      if (matchId != null &&
          matchId.isNotEmpty &&
          previous?.acceptedMatchId != matchId) {
        context.go(GameRoutes.match(next.acceptedGameCode ?? widget.mode.gameCode, matchId));
      }
    });

    return PopScope(
        canPop: state.myState != LobbyPlayerState.challenged,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (state.myState == LobbyPlayerState.challenged) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Resolve the challenge before leaving.')));
            return;
          }
          if (state.myState == LobbyPlayerState.ready) {
            final leave = await _confirmLeaveReady(context);
            if (leave != true || !context.mounted) return;
          }
          await controller.leave();
          if (context.mounted) context.pop();
        },
        child: Scaffold(
          appBar: AppBar(
            title:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${GameRoutes.displayName(widget.mode.gameCode)} • $stake'),
              Text('${state.onlineCount} online • ${state.readyCount} ready',
                  style: Theme.of(context).textTheme.labelSmall),
            ]),
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  if (socket != GameSocketStatus.connected || state.loading)
                    _ConnectionStrip(
                        text: state.loading
                            ? 'Recovering live lobby…'
                            : 'Reconnecting…'),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.screen),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (state.error != null) ...[
                            const SizedBox(height: 8),
                            Text(state.error!,
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.error))
                          ],
                          if (state.error != null) const SizedBox(height: 12),
                          _MyStatusPanel(
                              state: state,
                              stake: stake,
                              onReady: controller.ready,
                              onUnready: controller.unready,
                              onInvite: () async {
                                if (!_hasGoal) return controller.createInvite();
                                final goal = await pickGoal(context, confirmLabel: 'Create invite');
                                if (goal != null) await controller.createInvite(tokensToWin: goal);
                              }),
                          const SizedBox(height: 12),
                          SegmentedButton<int>(
                            segments: [
                              const ButtonSegment(
                                  value: 0,
                                  label: Text('Players'),
                                  icon: Icon(Icons.groups_outlined)),
                              ButtonSegment(
                                value: 1,
                                label: Text(state.chatUnread > 0
                                    ? 'Chat ${state.chatUnread}'
                                    : 'Chat'),
                                icon: const Icon(Icons.chat_bubble_outline),
                              ),
                            ],
                            selected: {_tab},
                            onSelectionChanged: (value) {
                              setState(() => _tab = value.first);
                              if (_tab == 1) controller.clearChatUnread();
                            },
                          ),
                        ]),
                  ),
                  Expanded(
                    child: _tab == 0
                        ? _PlayersTab(state: state, controller: controller)
                        : ChatThread(
                            lines: [
                              for (final m in state.messages)
                                ChatLine(
                                  id: m.id,
                                  text: m.text,
                                  senderName: m.sender.displayName,
                                  mine: m.sender.userId == state.currentUserId,
                                  createdAt: m.createdAt,
                                ),
                            ],
                            sending: state.sendingMessage,
                            emptyText: 'No messages yet. Say good luck 👋',
                            onSend: controller.sendMessage,
                          ),
                  ),
                ],
              ),
              if (challenge != null)
                _ChallengePanel(
                  isIncoming: challenge.opponentId == selfId,
                  inviteCode: challenge.isInvite ? challenge.displayInviteCode : null,
                  title: challenge.challengerName ??
                      challenge.opponentName ??
                      'Player',
                  stake: stake,
                  gameName: GameRoutes.displayName(widget.mode.gameCode),
                  tokensToWin: _hasGoal ? challenge.tokensToWin : null,
                  expiresAt: challenge.expiresAt,
                  busy: state.busy,
                  onAccept: controller.accept,
                  onReject: controller.reject,
                  onCancel: controller.cancel,
                ),
            ],
          ),
        ));
  }
}

Future<bool?> _confirmLeaveReady(BuildContext context) => showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave lobby?'),
        content: const Text('You will no longer be ready.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stay')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Leave')),
        ],
      ),
    );

class _ConnectionStrip extends StatelessWidget {
  const _ConnectionStrip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Text(text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall),
      );
}

class _MyStatusPanel extends StatelessWidget {
  const _MyStatusPanel(
      {required this.state,
      required this.stake,
      required this.onReady,
      required this.onUnready,
      required this.onInvite});
  final LiveLobbyState state;
  final String stake;
  final VoidCallback onReady;
  final VoidCallback onUnready;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final name = state.selfPlayer?.displayName ?? 'You';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('YOU', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 3),
        Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(_statusText(state), style: Theme.of(context).textTheme.bodyMedium),
        Text('Stake $stake', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        if (state.myState == LobbyPlayerState.online)
          FilledButton.icon(
              onPressed: state.busy || state.isRecovering ? null : onReady,
              icon: state.busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_circle_outline),
              label: const Text("I'm Ready"))
        else if (state.myState == LobbyPlayerState.ready)
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonal(onPressed: null, child: const Text('Ready ✓')),
            OutlinedButton(
                onPressed: state.busy || state.isRecovering ? null : onUnready,
                child: const Text('Cancel Ready')),
          ]),
        if (state.activeChallenge == null) ...[
          const SizedBox(height: 4),
          TextButton.icon(
              onPressed: state.busy || state.isRecovering ? null : onInvite,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Invite a friend with a code')),
        ],
      ]),
    );
  }

  String _statusText(LiveLobbyState state) {
    final challenge = state.activeChallenge;
    if (challenge != null && challenge.isInvite) return 'Waiting for your friend to join…';
    if (challenge != null) {
      final name =
          challenge.challengerName ?? challenge.opponentName ?? 'player';
      return challenge.opponentId == state.selfPlayer?.userId
          ? 'Game request received'
          : 'Waiting for $name…';
    }
    return switch (state.myState) {
      LobbyPlayerState.ready => '✓ You are ready. Choose a ready player below.',
      LobbyPlayerState.challenged => 'Challenge pending.',
      LobbyPlayerState.online => 'Ready to play?',
    };
  }
}

class _PlayersTab extends StatelessWidget {
  const _PlayersTab({required this.state, required this.controller});
  final LiveLobbyState state;
  final LiveLobbyController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen, 0, AppSpacing.screen, AppSpacing.screen),
      children: [
        Text('Ready now', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (state.loading)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator()))
        else if (state.orderedPlayers.isEmpty)
          const _EmptyPlayers()
        else
          ...state.orderedPlayers.map((player) => _PlayerTile(
                player: player,
                connecting: state.pendingChallengeUserId == player.userId,
                // Not being ready yet is fine: Connect readies you too.
                canConnect: state.myState != LobbyPlayerState.challenged &&
                    player.state == LobbyPlayerState.ready &&
                    state.activeChallenge == null &&
                    !state.busy &&
                    !state.isRecovering,
                onConnect: () async {
                  // "First to N home" is a Ludo option; other games connect directly.
                  if (state.mode?.gameCode != GameCodes.ludo) return controller.challenge(player);
                  final goal = await pickGoal(context, confirmLabel: 'Connect');
                  if (goal != null) await controller.challenge(player, tokensToWin: goal);
                },
                onMessage: () => context.push('/chats/${player.userId}', extra: player.displayName),
              )),
      ],
    );
  }
}

class _EmptyPlayers extends StatelessWidget {
  const _EmptyPlayers();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text("You're early.\nStay ready while other players join.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile(
      {required this.player,
      required this.canConnect,
      required this.connecting,
      required this.onConnect,
      required this.onMessage});
  final LobbyPlayer player;
  final bool canConnect;
  final bool connecting;
  final VoidCallback onConnect;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: canConnect,
      label: canConnect
          ? 'Connect to ${player.displayName}'
          : '${player.displayName}, ${_status(player.state)}',
      child: ListTile(
        leading: CircleAvatar(
            child: Text(player.displayName.isNotEmpty
                ? player.displayName[0].toUpperCase()
                : '?')),
        title: Text(player.displayName,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(_status(player.state)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Message ${player.displayName}',
              onPressed: onMessage,
              icon: const Icon(Icons.chat_bubble_outline_rounded),
            ),
            if (player.state == LobbyPlayerState.ready)
              FilledButton(
                onPressed: canConnect && !connecting ? onConnect : null,
                child: connecting
                    ? const Row(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('Sending…'),
                      ])
                    : const Text('Connect'),
              )
            else
              Text(_status(player.state), style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }

  String _status(LobbyPlayerState state) => switch (state) {
        LobbyPlayerState.ready => 'Ready',
        LobbyPlayerState.challenged => 'Busy',
        LobbyPlayerState.online => 'Online'
      };
}

/// "👑👑 First to 2 home" under a challenge or invite.
class _GoalLine extends StatelessWidget {
  const _GoalLine({required this.tokensToWin});
  final int tokensToWin;

  @override
  Widget build(BuildContext context) => Row(children: [
        CrownRow(count: tokensToWin, size: 18, emptyColor: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 8),
        Text(goalLabel(tokensToWin), style: const TextStyle(fontWeight: FontWeight.w700)),
      ]);
}

class _ChallengePanel extends StatefulWidget {
  const _ChallengePanel(
      {required this.isIncoming,
      this.inviteCode,
      required this.title,
      required this.stake,
      required this.gameName,
      this.tokensToWin,
      required this.expiresAt,
      required this.busy,
      required this.onAccept,
      required this.onReject,
      required this.onCancel});
  final bool isIncoming;
  /// Set for an outgoing invite: shown instead of an opponent name.
  final String? inviteCode;
  final String title;
  final String stake;
  final String gameName;

  /// Ludo goal; null for games without one.
  final int? tokensToWin;
  final DateTime expiresAt;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onCancel;

  @override
  State<_ChallengePanel> createState() => _ChallengePanelState();
}

class _ChallengePanelState extends State<_ChallengePanel> {
  Widget _invite(BuildContext context, String code, String timeText) => Align(
        alignment: Alignment.bottomCenter,
        child: Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Invite a friend', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Share this code. Your friend opens ${widget.gameName} → Join with code.\n${widget.gameName} • ${widget.stake} • $timeText'),
              if (widget.tokensToWin case final goal?) ...[
                const SizedBox(height: 8),
                _GoalLine(tokensToWin: goal),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: SelectableText(code,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 2)),
                ),
                IconButton(
                  tooltip: 'Copy code',
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied')));
                  },
                ),
              ]),
              const SizedBox(height: 8),
              OutlinedButton(
                  onPressed: widget.busy ? null : widget.onCancel,
                  child: Text(widget.busy ? 'Cancelling…' : 'Cancel invite')),
            ]),
          ),
        ),
      );

  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds =
        widget.expiresAt.difference(DateTime.now().toUtc()).inSeconds;
    final timeText = seconds <= 0
        ? 'Waiting for server…'
        : seconds >= 60
            ? 'Expires in ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}'
            : 'Expires in ${seconds}s';
    final code = widget.inviteCode;
    if (code != null) return _invite(context, code, timeText);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                    widget.isIncoming
                        ? 'Game Request'
                        : 'Waiting for ${widget.title}',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(widget.isIncoming
                    ? '${widget.title} wants to play ${widget.gameName} • ${widget.stake}\n$timeText'
                    : '${widget.gameName} • ${widget.stake}\n$timeText'),
                if (widget.tokensToWin case final goal?) ...[
                  const SizedBox(height: 8),
                  _GoalLine(tokensToWin: goal),
                ],
                const SizedBox(height: 12),
                if (widget.isIncoming)
                  Row(children: [
                    Expanded(
                        child: OutlinedButton(
                            onPressed: widget.busy ? null : widget.onReject,
                            child: const Text('Reject'))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: FilledButton(
                            onPressed: widget.busy ? null : widget.onAccept,
                            child: widget.busy
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Text('Accept')))
                  ])
                else
                  OutlinedButton(
                      onPressed: widget.busy ? null : widget.onCancel,
                      child: widget.busy
                          ? const Text('Cancelling…')
                          : const Text('Cancel')),
              ]),
        ),
      ),
    );
  }
}
