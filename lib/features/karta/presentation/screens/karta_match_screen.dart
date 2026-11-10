import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/audio/game_sound_service.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/theme/app_theme.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/chat/application/match_chat_controller.dart';
import 'package:friends_game_app/features/game_hub/domain/game_routes.dart';
import 'package:friends_game_app/features/karta/application/karta_match_controller.dart';
import 'package:friends_game_app/features/karta/domain/karta_models.dart';
import 'package:friends_game_app/features/karta/presentation/widgets/karta_cards.dart';
import 'package:friends_game_app/features/match/application/match_reactions_controller.dart';
import 'package:friends_game_app/features/match/presentation/match_sheets.dart';
import 'package:friends_game_app/features/match/presentation/widgets/celebration.dart';
import 'package:friends_game_app/features/match/presentation/widgets/match_chrome.dart';
import 'package:friends_game_app/features/profile/presentation/controllers/preferences_controller.dart';

/// Karta Lat Lat table. The server shuffles, deals and decides; this screen
/// lets the chooser pick a rank, lets the starter turn ("lat") the cards,
/// and shows each round's result with its fairness check.
class KartaMatchScreen extends ConsumerStatefulWidget {
  const KartaMatchScreen({super.key, required this.matchId});
  final String matchId;

  @override
  ConsumerState<KartaMatchScreen> createState() => _KartaMatchScreenState();
}

class _KartaMatchScreenState extends ConsumerState<KartaMatchScreen> with WidgetsBindingObserver {
  String? _pickedRank;

  /// The finished round stays on the table for a moment before the next one.
  KartaRoundEnd? _shownRound;
  Timer? _roundTimer;
  bool _celebrating = false;
  Timer? _celebrationTimer;

  static const _roundPause = Duration(milliseconds: 2400);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(gameSoundServiceProvider).preload();
    Future.microtask(() => ref.read(kartaMatchControllerProvider.notifier).join(widget.matchId));
    Future.microtask(() => ref.read(matchChatControllerProvider.notifier).load(widget.matchId));
    Future.microtask(() => ref.read(matchReactionsProvider.notifier).attach(widget.matchId));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(ref.read(kartaMatchControllerProvider.notifier).recover());
  }

  @override
  void dispose() {
    _roundTimer?.cancel();
    _celebrationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _play(GameSound sound, {double volume = 1}) => ref.read(gameSoundServiceProvider).play(sound, volume: volume);
  void _haptic(void Function() effect) {
    if (ref.read(playerPreferencesProvider).hapticsEnabled) effect();
  }

  void _onChange(KartaMatchViewState? previous, KartaMatchViewState next) {
    final me = ref.read(authControllerProvider).user?.id;
    final before = previous?.game;
    final game = next.game;
    if (before == null || game == null) return;

    if (game.dealt.length > before.dealt.length || next.roundEnd?.seq != previous?.roundEnd?.seq) _play(GameSound.step, volume: 0.6);
    if (next.roundEnd != null && next.roundEnd!.seq != previous?.roundEnd?.seq) {
      final mine = next.roundEnd!.result.winnerId == me;
      _play(mine ? GameSound.home : GameSound.capture);
      _haptic(mine ? HapticFeedback.mediumImpact : HapticFeedback.lightImpact);
      setState(() => _shownRound = next.roundEnd);
      _roundTimer?.cancel();
      _roundTimer = Timer(_roundPause, () {
        if (!mounted) return;
        setState(() => _shownRound = null);
        if (ref.read(kartaMatchControllerProvider).game?.finished == true) _celebrate();
      });
    } else if (game.finished && !before.finished && _shownRound == null) {
      _celebrate(); // e.g. a resignation
    }
    if (!game.finished && game.currentPlayerId == me && before.currentPlayerId != me && game.calling) {
      _play(GameSound.yourTurn, volume: 0.7);
    }
    if (next.autoPlayedSeq != previous?.autoPlayedSeq && next.autoPlayedBy != null) {
      final text = next.autoPlayedBy == me
          ? 'Time ran out, so we played for you (${next.timing.strikes[me] ?? 0}/${next.timing.maxStrikes}).'
          : '${next.nameOf(next.autoPlayedBy)} is away, auto-played.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
    }
  }

  void _celebrate() {
    final game = ref.read(kartaMatchControllerProvider).game;
    final me = ref.read(authControllerProvider).user?.id;
    _play(game?.winnerId == me ? GameSound.win : GameSound.lose);
    setState(() => _celebrating = true);
    _celebrationTimer?.cancel();
    _celebrationTimer = Timer(const Duration(milliseconds: 2800), () {
      if (mounted) setState(() => _celebrating = false);
    });
  }

  Future<void> _call() async {
    final rank = _pickedRank;
    if (rank == null) return;
    _haptic(HapticFeedback.lightImpact);
    if (await ref.read(kartaMatchControllerProvider.notifier).call(rank) && mounted) setState(() => _pickedRank = null);
  }

  void _flip() {
    _haptic(HapticFeedback.mediumImpact);
    ref.read(kartaMatchControllerProvider.notifier).flip();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(kartaMatchControllerProvider, _onChange);
    final match = ref.watch(kartaMatchControllerProvider);
    final me = ref.watch(authControllerProvider.select((auth) => auth.user?.id));
    final socket = ref.watch(gameSocketStatusProvider);
    final chat = ref.watch(matchChatControllerProvider);
    final reactions = ref.watch(matchReactionsProvider);
    final soundOn = ref.watch(playerPreferencesProvider.select((p) => p.soundEnabled));
    final game = match.game;

    if (match.loading || game == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Karta Lat Lat')),
        body: Center(
          child: match.error == null
              ? const CircularProgressIndicator()
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(padding: const EdgeInsets.all(24), child: Text(match.error!, textAlign: TextAlign.center)),
                  FilledButton(
                      onPressed: () => ref.read(kartaMatchControllerProvider.notifier).join(widget.matchId),
                      child: const Text('Try again')),
                ]),
        ),
      );
    }

    final opponent = game.otherThan(me);
    final shown = _shownRound;
    final dealt = shown?.dealt ?? game.dealt;
    final connected = socket == GameSocketStatus.connected;
    final myTurn = shown == null && !game.finished && game.currentPlayerId == me;
    final canAct = myTurn && connected && match.pendingCommandId == null && !match.recovering;
    final calledRank = shown?.result.rank ?? game.calledRank;

    Widget seat(String? userId) => _Seat(
          name: userId == me ? 'You' : match.nameOf(userId),
          score: game.scoreOf(userId),
          target: game.targetScore,
          role: shown != null || game.finished ? null : (game.starterId == userId ? 'STARTER' : 'CHOOSER'),
          active: shown == null && !game.finished && game.currentPlayerId == userId,
          turnEndsAt: game.currentPlayerId == userId ? match.timing.turnEndsAt : null,
          turnSeconds: match.turnSeconds,
          strikes: match.timing.strikes[userId] ?? 0,
          reaction: reactions[userId]?.reaction.display,
          reactionSeq: reactions[userId]?.seq ?? 0,
        );

    return Theme(
      data: AppTheme.dark(),
      child: Scaffold(
        backgroundColor: KartaPalette.feltBottom,
        body: Stack(fit: StackFit.expand, children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(center: Alignment(0, -0.1), radius: 1.1, colors: [KartaPalette.feltTop, KartaPalette.feltBottom]),
            ),
          ),
          SafeArea(
            child: Column(children: [
              MatchConnectionBanner(status: socket, recovering: match.recovering),
              MatchTopBar(
                unread: chat.unread,
                soundOn: soundOn,
                recovering: match.recovering,
                onExit: () => _exit(game),
                onChat: () => openMatchChat(context, ref),
                onReact: () => showMatchReactionPicker(context, ref),
                onToggleSound: () => ref.read(playerPreferencesProvider.notifier).setSound(!soundOn),
                onMenu: () => _openMenu(game),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(children: [
                    seat(opponent),
                    const SizedBox(height: 8),
                    _Lane(
                        cards: dealt.where((d) => d.playerId == opponent).map((d) => d.card).toList(),
                        winning: shown?.result.winnerId == opponent ? shown!.result.card : null),
                    Expanded(
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        _Deck(cardsLeft: 52 - dealt.length, enabled: canAct && !game.calling, onTap: _flip),
                        const SizedBox(width: 22),
                        Flexible(
                          child: _CalledRank(
                            rank: calledRank,
                            caller: calledRank == null ? null : (game.callerId == me ? 'You' : match.nameOf(game.callerId)),
                            left: shown == null ? game.calledLeft : null,
                            round: shown?.result.round ?? game.round,
                          ),
                        ),
                      ]),
                    ),
                    _Lane(
                        cards: dealt.where((d) => d.playerId == me).map((d) => d.card).toList(),
                        winning: shown?.result.winnerId == me ? shown!.result.card : null),
                    const SizedBox(height: 8),
                    seat(me),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (match.error != null) MatchInlineMessage(message: match.error!),
                  if (shown != null)
                    _RoundBanner(round: shown, mine: shown.result.winnerId == me, winner: match.nameOf(shown.result.winnerId))
                  else if (game.finished)
                    FilledButton.icon(
                      onPressed: () => context.pushReplacement(GameRoutes.result(GameCodes.karta, widget.matchId)),
                      icon: const Icon(Icons.emoji_events_outlined),
                      label: const Text('View result'),
                    )
                  else if (myTurn && game.calling)
                    _RankPicker(picked: _pickedRank, enabled: canAct, onPick: (rank) => setState(() => _pickedRank = rank), onCall: _call)
                  else if (myTurn)
                    _LatButton(enabled: canAct, forMe: game.receiverId == me, receiver: match.nameOf(game.receiverId), onTap: _flip)
                  else
                    Text(
                      !connected
                          ? 'Reconnecting…'
                          : game.calling
                              ? '${match.nameOf(game.currentPlayerId)} is choosing a rank…'
                              : '${match.nameOf(game.starterId)} deals · next card ${game.receiverId == me ? 'for you' : 'for ${match.nameOf(game.receiverId)}'}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w600),
                    ),
                ]),
              ),
            ]),
          ),
          if (shown != null)
            IgnorePointer(
                child: Confetti(key: ValueKey('round-${shown.seq}'), seed: shown.seq, count: shown.result.winnerId == me ? 60 : 24)),
          if (_celebrating)
            Positioned.fill(
              child: WinCelebration(
                title: game.winnerId == me ? 'YOU WON!' : '${match.nameOf(game.winnerId).toUpperCase()} WON',
                subtitle: game.finishReason == 'RESIGN'
                    ? 'By resignation'
                    : '${game.scoreOf(game.winnerId)} – ${game.scoreOf(game.otherThan(game.winnerId))}',
                onDismiss: () => setState(() => _celebrating = false),
              ),
            ),
        ]),
      ),
    );
  }

  Future<void> _exit(KartaGame game) async {
    if (game.finished) {
      context.pushReplacement(GameRoutes.result(GameCodes.karta, widget.matchId));
      return;
    }
    if (!await confirmLeaveMatch(context) || !mounted) return;
    final ok = await ref.read(kartaMatchControllerProvider.notifier).resign();
    if (ok && mounted) context.go('/home');
  }

  Future<void> _openMenu(KartaGame game) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('Fair deck'),
              subtitle: Text(
                  'Sealed before the call: ${game.deckCommitment.length >= 12 ? game.deckCommitment.substring(0, 12) : game.deckCommitment}…'),
              onTap: () {
                Navigator.pop(sheet);
                showKartaRules(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('How to play'),
              onTap: () {
                Navigator.pop(sheet);
                showKartaRules(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.sync_rounded),
              title: const Text('Sync game'),
              onTap: () {
                Navigator.pop(sheet);
                ref.read(kartaMatchControllerProvider.notifier).recover();
              },
            ),
            if (!game.finished)
              ListTile(
                leading: Icon(Icons.flag_outlined, color: Theme.of(context).colorScheme.error),
                title: Text('Resign', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: () async {
                  Navigator.pop(sheet);
                  if (await confirmLeaveMatch(context)) await ref.read(kartaMatchControllerProvider.notifier).resign();
                },
              ),
          ]),
        ),
      );
}

/// Rules in plain words (also reachable from the lobby).
Future<void> showKartaRules(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ካርታ ላጥ ላጥ · Karta Lat Lat', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            SizedBox(height: 12),
            _Rule(Icons.record_voice_over_outlined, 'Choose a rank', 'The chooser names a rank (A to K). Suits do not matter.'),
            _Rule(Icons.style_outlined, 'Lat lat!', 'The starter turns every card: one for the chooser, one for themselves, and so on.'),
            _Rule(Icons.emoji_events_outlined, 'Catch it', 'Whoever gets the first card of that rank wins the round and starts the next one.'),
            _Rule(Icons.workspace_premium_outlined, 'First to 3', 'The first player to win 3 rounds wins the match. You can resign at any time.'),
            _Rule(Icons.verified_user_outlined, 'Fair deck',
                'Each deck is sealed (a secure fingerprint) before the call and revealed after the round. The app checks it.'),
          ]),
        ),
      ),
    );

class _Rule extends StatelessWidget {
  const _Rule(this.icon, this.title, this.text);
  final IconData icon;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(text),
      );
}

class _Seat extends StatelessWidget {
  const _Seat({
    required this.name,
    required this.score,
    required this.target,
    required this.role,
    required this.active,
    required this.turnEndsAt,
    required this.turnSeconds,
    required this.strikes,
    this.reaction,
    this.reactionSeq = 0,
  });
  final String name;
  final int score;
  final int target;

  /// STARTER (deals) or CHOOSER (names the rank); null between rounds.
  final String? role;
  final bool active;
  final DateTime? turnEndsAt;
  final int turnSeconds;
  final int strikes;
  final String? reaction;
  final int reactionSeq;

  @override
  Widget build(BuildContext context) {
    final remaining = turnEndsAt?.difference(DateTime.now());
    final fraction = remaining == null ? 0.0 : (remaining.inMilliseconds / (turnSeconds * 1000)).clamp(0.0, 1.0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: active ? 0.32 : 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: active ? KartaPalette.gold : Colors.white.withValues(alpha: 0.08), width: active ? 1.6 : 1),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: KartaPalette.gold.withValues(alpha: 0.18),
            child: Text(name.characters.first.toUpperCase(), style: const TextStyle(color: KartaPalette.gold, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(children: [
              Flexible(
                child: Text(name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              if (role != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: role == 'STARTER' ? KartaPalette.gold : Colors.transparent,
                    border: Border.all(color: KartaPalette.gold),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    role!,
                    style: TextStyle(
                      color: role == 'STARTER' ? KartaPalette.ink : KartaPalette.gold,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
              if (reaction != null) ...[
                const SizedBox(width: 8),
                TweenAnimationBuilder<double>(
                  key: ValueKey(reactionSeq),
                  tween: Tween(begin: 0.4, end: 1),
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.elasticOut,
                  builder: (context, s, child) => Transform.scale(scale: s, child: child),
                  child: Text(reaction!, style: const TextStyle(fontSize: 18)),
                ),
              ],
            ]),
          ),
          // Score pips: first to [target].
          for (var i = 0; i < target; i++)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < score ? KartaPalette.gold : Colors.transparent,
                  border: Border.all(color: KartaPalette.gold, width: 1.6),
                ),
              ),
            ),
        ]),
        if (strikes > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Away $strikes×', style: const TextStyle(color: Color(0xFFFF8A65), fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        // Move clock: empties smoothly until the deadline.
        if (active && remaining != null && fraction > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: TweenAnimationBuilder<double>(
              key: ValueKey(turnEndsAt),
              tween: Tween(begin: fraction, end: 0),
              duration: remaining,
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 4,
                  backgroundColor: Colors.white12,
                  color: value > 0.33 ? KartaPalette.gold : const Color(0xFFFF7043),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// One player's cards this round, overlapped, newest on the right.
class _Lane extends StatelessWidget {
  const _Lane({required this.cards, this.winning});
  final List<KartaCard> cards;
  final KartaCard? winning;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: kartaCardSize(52).height + 6,
        child: LayoutBuilder(builder: (context, constraints) {
          const width = 52.0;
          final visible = cards.length > 9 ? cards.sublist(cards.length - 9) : cards;
          final step = visible.length <= 1 ? 0.0 : ((constraints.maxWidth - width) / (visible.length - 1)).clamp(0.0, 30.0);
          final total = width + step * (visible.length - 1);
          final left = (constraints.maxWidth - total) / 2;
          return Stack(children: [
            if (cards.isEmpty) Center(child: Text('—', style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 18))),
            for (var i = 0; i < visible.length; i++)
              Positioned(
                left: left + i * step,
                top: 3,
                child: KartaFlipIn(
                  key: ValueKey('${cards.length - visible.length + i}-${visible[i].label}'),
                  card: visible[i],
                  width: width,
                  highlight: winning != null && i == visible.length - 1 && visible[i] == winning,
                ),
              ),
          ]);
        }),
      );
}

class _Deck extends StatelessWidget {
  const _Deck({required this.cardsLeft, required this.enabled, required this.onTap});
  final int cardsLeft;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: enabled,
        label: 'Deck, $cardsLeft cards. ${enabled ? 'Tap to turn the next card.' : ''}',
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 76,
              height: kartaCardSize(70).height + 8,
              child: Stack(children: [
                for (var i = 0; i < 3; i++) Positioned(left: i * 2.0, top: 8 - i * 3.0, child: const KartaCardBack(width: 70)),
              ]),
            ),
            const SizedBox(height: 6),
            Text('$cardsLeft left',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

/// The called rank as a big glowing card (face down until it is called).
class _CalledRank extends StatelessWidget {
  const _CalledRank({required this.rank, required this.caller, required this.left, required this.round});
  final String? rank;
  final String? caller;
  final int? left;
  final int round;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          'ROUND $round',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack), child: child),
          child: rank == null
              ? const KartaCardBack(key: ValueKey('back'), width: 70)
              : KartaRankCard(key: ValueKey(rank), rank: rank!, width: 70, glow: true),
        ),
        const SizedBox(height: 8),
        Text(
          caller == null ? 'Waiting for the call' : '$caller called${left != null ? ' · $left left' : ''}',
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ]);
}

/// The chooser picks a rank from a hand of rank cards, then confirms.
class _RankPicker extends StatelessWidget {
  const _RankPicker({required this.picked, required this.enabled, required this.onPick, required this.onCall});
  final String? picked;
  final bool enabled;
  final ValueChanged<String> onPick;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Choose a rank', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, constraints) {
          // Two rows (7 + 6) that always fit the screen width.
          final width = ((constraints.maxWidth - 6 * 6) / 7).clamp(30.0, 46.0);
          return Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 8, children: [
            for (final rank in kartaRanks)
              GestureDetector(
                onTap: enabled ? () => onPick(rank) : null,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 160),
                  offset: Offset(0, picked == rank ? -0.12 : 0),
                  child: KartaRankCard(rank: rank, width: width, selected: picked == rank),
                ),
              ),
          ]);
        }),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: KartaPalette.gold,
              foregroundColor: KartaPalette.ink,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: enabled && picked != null ? onCall : null,
            child: Text(picked == null ? 'Pick a card' : 'Call $picked', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ),
        ),
      ]);
}

/// The starter's button: says who the next card goes to ("for away" / "for me").
class _LatButton extends StatelessWidget {
  const _LatButton({required this.enabled, required this.forMe, required this.receiver, required this.onTap});
  final bool enabled;
  final bool forMe;
  final String receiver;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: KartaPalette.gold,
            foregroundColor: KartaPalette.ink,
            minimumSize: const Size.fromHeight(56),
          ),
          onPressed: enabled ? onTap : null,
          icon: const Icon(Icons.style_rounded),
          label: Text(
            forMe ? 'LAT!  For me' : 'LAT!  For $receiver',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: 0.5),
          ),
        ),
      );
}

class _RoundBanner extends StatelessWidget {
  const _RoundBanner({required this.round, required this.mine, required this.winner});
  final KartaRoundEnd round;
  final bool mine;
  final String winner;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.7, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.elasticOut,
        builder: (context, s, child) => Transform.scale(scale: s, child: child),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            mine ? 'YOU TAKE ROUND ${round.result.round}!' : '${winner.toUpperCase()} TAKES ROUND ${round.result.round}',
            style: const TextStyle(color: KartaPalette.gold, fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            '${round.result.card.label} on card ${round.result.flips}  ·  ${round.verified ? '✓ Fair deck verified' : 'Deck check unavailable'}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ]),
      );
}
