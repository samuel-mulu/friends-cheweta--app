import 'package:flutter/material.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
import 'package:friends_game_app/core/theme/app_type.dart';

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
    this.badge,
  });

  /// Shown between Exit and the actions (e.g. the game type).
  final Widget? badge;

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
    // Dark translucent pills, so they sit on any table (navy, wood, felt).
    Widget pill({required Widget child, VoidCallback? onTap, String? tooltip}) => Tooltip(
          message: tooltip ?? '',
          child: Material(
            color: Colors.black.withValues(alpha: 0.32),
            shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.14))),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 40, minWidth: 44),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: child,
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Row(children: [
        pill(
          onTap: onExit,
          tooltip: 'Exit match',
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.chevron_left_rounded, size: 18, color: AppColors.dangerSoft),
            Text('Exit', style: AppType.ui(size: 14.5, weight: FontWeight.w700, color: AppColors.dangerSoft)),
          ]),
        ),
        // The badge takes the free middle, and only when it fits (small phones
        // keep every button; the type is also in the menu's rules).
        Expanded(
          child: badge == null
              ? const SizedBox.shrink()
              : LayoutBuilder(
                  builder: (context, box) => box.maxWidth < 88
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: badge)),
                        ),
                ),
        ),
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
    return Material(
      color: AppColors.raised,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(children: [
          const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: AppType.ui(size: 13, weight: FontWeight.w600, color: AppColors.ink))),
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
