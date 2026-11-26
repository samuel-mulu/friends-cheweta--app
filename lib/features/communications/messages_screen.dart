import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:friends_game_app/core/errors/app_failure.dart';
import 'package:friends_game_app/core/widgets/app_error_view.dart';
import 'package:friends_game_app/core/widgets/ui.dart';
import 'package:friends_game_app/features/chat/application/chat_inbox_controller.dart';
import 'package:friends_game_app/features/communications/communications_controllers.dart';
import 'package:friends_game_app/features/communications/communications_repository.dart';

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _markOnOpen = false;
  int _lastTab = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)..addListener(_tabChanged);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _tabChanged() {
    if (_tabs.index == _lastTab) return;
    _lastTab = _tabs.index;
    _markOnOpen = _lastTab == 1;
    if (_markOnOpen) {
      final state = ref.read(feedbackControllerProvider);
      unawaited(_markSeenWhenReady(state));
      unawaited(ref.read(feedbackControllerProvider.notifier).refresh());
    }
  }

  Future<void> _markSeenWhenReady(FeedbackState state) async {
    final inbox = state.inbox;
    if (!_markOnOpen ||
        inbox == null ||
        state.loading ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _markOnOpen = false;
    if (inbox.unreadCount == 0) return;
    try {
      await ref
          .read(feedbackControllerProvider.notifier)
          .markSeen(inbox.seenThrough);
    } on AppFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedbackCount = ref.watch(feedbackControllerProvider
        .select((value) => value.inbox?.unreadCount ?? 0));
    final chatCount = ref.watch(
        chatInboxControllerProvider.select((value) => value.unreadTotal));
    ref.listen(feedbackControllerProvider,
        (_, state) => unawaited(_markSeenWhenReady(state)));

    final tabs = TabBar(
      controller: _tabs,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      tabs: [
        const Tab(text: 'Announcements'),
        Tab(
          child: Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Feedback'),
              if (feedbackCount > 0) Badge(label: Text(_count(feedbackCount))),
            ],
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        bottom: PreferredSize(
          preferredSize: tabs.preferredSize,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: tabs,
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(children: [
            Card(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: ListTile(
                leading: Badge(
                    isLabelVisible: chatCount > 0,
                    label: Text(_count(chatCount)),
                    child: const Icon(Icons.forum_outlined)),
                title: const Text('Player chat'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/chats'),
              ),
            ),
            Expanded(
                child: TabBarView(
                    controller: _tabs,
                    children: const [_Announcements(), _Feedback()])),
          ]),
        ),
      ),
    );
  }
}

String _count(int value) => value > 99 ? '99+' : '$value';

class _Announcements extends ConsumerWidget {
  const _Announcements();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(broadcastControllerProvider);
    final controller = ref.read(broadcastControllerProvider.notifier);
    final inbox = state.inbox;
    return _InboxList(
      loading: state.loading,
      error: state.error,
      hasLoaded: inbox != null,
      hasMore: inbox?.hasMore == true,
      more: controller.loadMore,
      refresh: controller.refresh,
      emptyText: 'No announcements yet.',
      children: [
        for (final notice in inbox?.items ?? const <BroadcastNotice>[])
          _AnnouncementCard(key: ValueKey(notice.id), notice: notice),
      ],
    );
  }
}

class _AnnouncementCard extends ConsumerStatefulWidget {
  const _AnnouncementCard({super.key, required this.notice});
  final BroadcastNotice notice;

  @override
  ConsumerState<_AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends ConsumerState<_AnnouncementCard> {
  bool _dismissing = false;

  Future<void> _dismiss() async {
    setState(() => _dismissing = true);
    try {
      await ref
          .read(broadcastControllerProvider.notifier)
          .dismiss(widget.notice);
    } on AppFailure catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _dismissing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final notice = widget.notice;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (notice.mode == BroadcastMode.persistent) ...[
            const StatusPill(label: 'Pinned'),
            const SizedBox(height: 8),
          ],
          Text(notice.title, style: text.titleMedium),
          const SizedBox(height: 4),
          Text(_formatDate(notice.createdAt), style: text.bodySmall),
          const SizedBox(height: 8),
          SelectableText(notice.body),
          if (notice.canDismiss)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                  onPressed: _dismissing ? null : _dismiss,
                  child: Text(_dismissing ? 'Dismissing…' : 'Dismiss')),
            ),
        ]),
      ),
    );
  }
}

class _Feedback extends ConsumerWidget {
  const _Feedback();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(feedbackControllerProvider);
    final controller = ref.read(feedbackControllerProvider.notifier);
    final inbox = state.inbox;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => showAppSheet<void>(context,
                  builder: (_) => const _FeedbackForm()),
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Send feedback'),
            )),
      ),
      Expanded(
          child: _InboxList(
        loading: state.loading,
        error: state.error,
        hasLoaded: inbox != null,
        hasMore: inbox?.hasMore == true,
        more: controller.loadMore,
        refresh: controller.refresh,
        emptyText: 'No feedback yet.',
        children: [
          for (final item in inbox?.items ?? const <PlayerFeedback>[])
            _FeedbackCard(item: item),
        ],
      )),
    ]);
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.item});
  final PlayerFeedback item;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                    item.message == null
                        ? 'Message from admin'
                        : item.category.label,
                    style: text.titleMedium),
                StatusPill(label: item.status),
              ]),
          const SizedBox(height: 4),
          Text(_formatDate(item.createdAt), style: text.bodySmall),
          if (item.message case final body?) ...[
            const SizedBox(height: 8),
            SelectableText(body)
          ],
          if (item.reply case final reply?) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.seen ? 'Admin reply' : 'New admin reply',
                        style: text.titleSmall),
                    const SizedBox(height: 4),
                    SelectableText(reply),
                    if (item.repliedAt != null) ...[
                      const SizedBox(height: 6),
                      Text(_formatDate(item.repliedAt!), style: text.bodySmall),
                    ],
                  ]),
            ),
          ],
        ]),
      ),
    );
  }
}

String _formatDate(DateTime date) =>
    DateFormat.yMMMd().add_jm().format(date.toLocal());

class _InboxList extends StatelessWidget {
  const _InboxList(
      {required this.loading,
      required this.error,
      required this.hasLoaded,
      required this.hasMore,
      required this.more,
      required this.refresh,
      required this.emptyText,
      required this.children});

  final bool loading;
  final String? error;
  final bool hasLoaded;
  final bool hasMore;
  final Future<void> Function() more;
  final Future<void> Function() refresh;
  final String emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (!hasLoaded && loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!hasLoaded && error != null) {
      return AppErrorView(message: error!, onRetry: refresh);
    }
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (error != null) ...[
            AppErrorView(message: error!, onRetry: refresh),
            const SizedBox(height: 8),
          ],
          if (children.isEmpty && error == null)
            Padding(
                padding: const EdgeInsets.all(20),
                child: Center(child: Text(emptyText))),
          for (final child in children)
            Padding(
                key: child.key,
                padding: const EdgeInsets.only(bottom: 10),
                child: child),
          if (hasMore)
            OutlinedButton(
                onPressed: loading ? null : more,
                child: Text(loading ? 'Loading…' : 'Load more')),
        ],
      ),
    );
  }
}

class _FeedbackForm extends ConsumerStatefulWidget {
  const _FeedbackForm();
  @override
  ConsumerState<_FeedbackForm> createState() => _FeedbackFormState();
}

class _FeedbackFormState extends ConsumerState<_FeedbackForm> {
  final _text = TextEditingController();
  final _form = GlobalKey<FormState>();
  FeedbackCategory _category = FeedbackCategory.feedback;
  String _request = const Uuid().v4();
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(feedbackControllerProvider.notifier)
          .send(_category, _text.text.trim(), _request);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('Feedback sent.')));
      final sheet = ModalRoute.of(context);
      if (sheet?.isActive == true) sheet!.navigator?.removeRoute(sheet);
    } on AppFailure catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = error.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_sending,
      child: Form(
          key: _form,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Send feedback', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<FeedbackCategory>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: FeedbackCategory.values
                  .map((value) =>
                      DropdownMenuItem(value: value, child: Text(value.label)))
                  .toList(),
              onChanged: _sending
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        _category = value;
                        _request = const Uuid().v4();
                      });
                    },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _text,
              readOnly: _sending,
              minLines: 3,
              maxLines: 6,
              maxLength: 1000,
              decoration: const InputDecoration(
                  labelText: 'Message', alignLabelWithHint: true),
              validator: (value) =>
                  value?.trim().isNotEmpty == true ? null : 'Enter a message.',
              onChanged: (_) => _request = const Uuid().v4(),
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
            FilledButton(
                onPressed: _sending ? null : _send,
                child: Text(_sending ? 'Sending…' : 'Send feedback')),
          ])),
    );
  }
}
