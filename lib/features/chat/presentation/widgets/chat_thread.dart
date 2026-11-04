import 'package:flutter/material.dart';

/// What one bubble shows; every chat (lobby, match, private) maps to this.
class ChatLine {
  const ChatLine({
    required this.id,
    required this.text,
    required this.senderName,
    required this.mine,
    required this.createdAt,
  });

  final String id;
  final String text;
  final String senderName;
  final bool mine;
  final DateTime createdAt;
}

/// Shared chat view: bubbles (mine on the right), newest always visible at the
/// bottom, and a composer. Group chats show sender names; private chats don't.
class ChatThread extends StatefulWidget {
  const ChatThread({
    super.key,
    required this.lines,
    required this.onSend,
    this.sending = false,
    this.showSenderNames = true,
    this.emptyText = 'No messages yet. Say hi 👋',
    this.error,
    this.onLoadOlder,
  });

  final List<ChatLine> lines;

  /// Returns true when the server accepted the message; on false the text is
  /// put back in the composer so nothing typed is lost.
  final Future<bool> Function(String text) onSend;
  final bool sending;
  final bool showSenderNames;
  final String emptyText;
  final String? error;

  /// Called when the user scrolls to the oldest loaded message.
  final VoidCallback? onLoadOlder;

  @override
  State<ChatThread> createState() => _ChatThreadState();
}

class _ChatThreadState extends State<ChatThread> {
  static const maxLength = 160;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(() {
      final hasText = _input.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
    _scroll.addListener(() {
      // List is reversed: maxScrollExtent is the oldest end.
      if (widget.onLoadOlder != null && _scroll.position.pixels >= _scroll.position.maxScrollExtent - 40) {
        widget.onLoadOlder!();
      }
    });
  }

  @override
  void didUpdateWidget(covariant ChatThread oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new message at the bottom: snap to it (reversed list, so offset 0).
    final newest = widget.lines.isEmpty ? null : widget.lines.last.id;
    final previousNewest = oldWidget.lines.isEmpty ? null : oldWidget.lines.last.id;
    if (newest != previousNewest && _scroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || widget.sending) return;
    _input.clear();
    final ok = await widget.onSend(text);
    if (!ok && mounted && _input.text.isEmpty) {
      _input.text = text;
      _input.selection = TextSelection.collapsed(offset: text.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lines;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: lines.isEmpty
              ? Center(child: Text(widget.emptyText, style: TextStyle(color: scheme.onSurfaceVariant)))
              : ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: lines.length,
                  itemBuilder: (context, index) {
                    final i = lines.length - 1 - index; // reversed
                    final line = lines[i];
                    final previous = i > 0 ? lines[i - 1] : null;
                    final firstOfGroup = previous == null || previous.mine != line.mine || previous.senderName != line.senderName;
                    return _Bubble(
                      line: line,
                      showName: widget.showSenderNames && !line.mine && firstOfGroup,
                      tight: !firstOfGroup,
                    );
                  },
                ),
        ),
        if (widget.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(widget.error!, style: TextStyle(color: scheme.error, fontSize: 12)),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    maxLength: maxLength,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: 'Message…',
                      counterText: '',
                      isDense: true,
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Send',
                  onPressed: _hasText && !widget.sending ? _send : null,
                  icon: widget.sending
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.line, required this.showName, required this.tight});
  final ChatLine line;
  final bool showName;
  final bool tight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = line.mine;
    final local = line.createdAt.toLocal();
    final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: EdgeInsets.only(top: tight ? 2 : 10),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
          child: Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (showName)
                Padding(
                  padding: const EdgeInsets.only(left: 10, bottom: 2),
                  child: Text(line.senderName, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: scheme.primary)),
                ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                decoration: BoxDecoration(
                  color: mine ? scheme.primary : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(mine ? 16 : 4),
                    bottomRight: Radius.circular(mine ? 4 : 16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(line.text, style: TextStyle(color: mine ? scheme.onPrimary : scheme.onSurface, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(
                      time,
                      style: TextStyle(
                        color: (mine ? scheme.onPrimary : scheme.onSurfaceVariant).withValues(alpha: 0.75),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
