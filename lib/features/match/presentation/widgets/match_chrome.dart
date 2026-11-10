import 'package:flutter/material.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';

/// Top bar, connection strip and inline error of the match screen.
class MatchTopBar extends StatelessWidget {
  const MatchTopBar({
    super.key,
    required this.unread,
    required this.soundOn,
    required this.recovering,
    required this.onExit,
    required this.onChat,
    required this.onReact,
    required this.onToggleSound,
    required this.onMenu,
  });

  final int unread;
  final bool soundOn;
  final bool recovering;
  final VoidCallback onExit;
  final VoidCallback onChat;
  final VoidCallback onReact;
  final VoidCallback onToggleSound;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    Widget pill({required Widget child, VoidCallback? onTap, String? tooltip}) => Tooltip(
          message: tooltip ?? '',
          child: Material(
            color: Colors.white.withValues(alpha: 0.1),
            shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.18))),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), child: child),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Row(children: [
        pill(
          onTap: onExit,
          tooltip: 'Exit match',
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.chevron_left_rounded, size: 18, color: Color(0xFFFF7A7A)),
            Text('Exit', style: TextStyle(color: Color(0xFFFF7A7A), fontWeight: FontWeight.w700)),
          ]),
        ),
        const Spacer(),
        pill(
          onTap: onToggleSound,
          tooltip: soundOn ? 'Mute sounds' : 'Unmute sounds',
          child: Icon(soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 8),
        pill(
          onTap: onReact,
          tooltip: 'Reactions',
          child: const Icon(Icons.emoji_emotions_outlined, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 8),
        pill(
          onTap: onChat,
          tooltip: 'Match chat',
          child: Badge(
            isLabelVisible: unread > 0,
            label: Text('$unread'),
            child: const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: Colors.white),
          ),
        ),
        const SizedBox(width: 8),
        pill(
          onTap: onMenu,
          tooltip: 'Menu',
          child: recovering
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.more_horiz_rounded, size: 18, color: Colors.white),
        ),
      ]),
    );
  }
}

class MatchConnectionBanner extends StatelessWidget {
  const MatchConnectionBanner({super.key, required this.status, required this.recovering});
  final GameSocketStatus status;
  final bool recovering;

  @override
  Widget build(BuildContext context) {
    if (status == GameSocketStatus.connected && !recovering) return const SizedBox.shrink();
    final text = recovering
        ? 'Recovering match…'
        : status == GameSocketStatus.connecting || status == GameSocketStatus.recovering
            ? 'Reconnecting…'
            : 'Connection lost — board preserved';
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer.withValues(alpha: 0.85),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onSecondaryContainer)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSecondaryContainer))),
        ]),
      ),
    );
  }
}

class MatchInlineMessage extends StatelessWidget {
  const MatchInlineMessage({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(10)),
        child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontSize: 13)),
      );
}
