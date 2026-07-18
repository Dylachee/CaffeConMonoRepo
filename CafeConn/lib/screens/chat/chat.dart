import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/dtos.dart';
import '../../state/cafe_state.dart';
import '../../widgets/app_widgets.dart';

/// The staff messenger, server-backed: three persistent channels, threads
/// with quoted replies, live task bubbles and the CafeBot slash commands.
/// History and unread badges survive reloads; delivery rides the staff WS.

String channelLabel(String channel) => switch (channel) {
      'floor' => L.t('Floor', 'Sala'),
      'kitchen' => L.chKitchen,
      'bar' => L.chBar,
      _ => L.chGeneral,
    };

Color channelColor(String channel) => switch (channel) {
      'floor' => AppColors.ok,
      'kitchen' => AppTheme.warning,
      'bar' => AppTheme.bar,
      _ => AppTheme.ink3,
    };

Color taskCategoryColor(String category) => switch (category) {
      'opening' => AppColors.ok,
      'closing' => AppColors.bill,
      'cleaning' => AppColors.bar,
      'inventory' => AppColors.gold,
      'service' => AppColors.kitchen,
      _ => AppColors.free,
    };

class StaffChatListScreen extends StatefulWidget {
  const StaffChatListScreen({super.key});

  @override
  State<StaffChatListScreen> createState() => _StaffChatListScreenState();
}

class _StaffChatListScreenState extends State<StaffChatListScreen> {
  bool _showTasks = false;
  String _taskFilter = 'mine';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<CafeState>().refreshPlanner());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final tasks = state.plannerTasks.where((task) {
      return switch (_taskFilter) {
        'available' => task.isAvailable,
        'done' => task.isDone && task.assigneeId == state.activeEmployeeId,
        _ => !task.isDone && task.assigneeId == state.activeEmployeeId,
      };
    }).toList();
    return AppScaffold(
      bottomNav: null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Header(title: L.team, subtitle: L.teamOnline, actions: [
          IconButton(
            tooltip: L.planner,
            icon: const Icon(Icons.event_note_outlined, color: AppTheme.ink),
            onPressed: () => GoRouter.of(context).push('/planner'),
          ),
          IconButton(
            tooltip: L.settings,
            icon: const Icon(Icons.settings_outlined, color: AppTheme.ink),
            onPressed: () => GoRouter.of(context).push('/settings'),
          ),
        ]),
        Container(
          height: 44,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.separator),
          ),
          child: Row(children: [
            Expanded(
              child: _TeamSegment(
                label: L.chats,
                icon: Icons.forum_outlined,
                selected: !_showTasks,
                onTap: () => setState(() => _showTasks = false),
              ),
            ),
            Expanded(
              child: _TeamSegment(
                label: L.myTasks,
                icon: Icons.task_alt_outlined,
                selected: _showTasks,
                onTap: () => setState(() => _showTasks = true),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        if (!state.backendConnected)
          Expanded(
            child: EmptyState(
                icon: Icons.chat_bubble_outline,
                title: L.chats,
                sub: L.chatConnectHint),
          )
        else if (_showTasks)
          Expanded(
            child: Column(children: [
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    CategoryChip(
                      label: L.myTasks,
                      active: _taskFilter == 'mine',
                      onTap: () => setState(() => _taskFilter = 'mine'),
                    ),
                    CategoryChip(
                      label: L.availableTasks,
                      active: _taskFilter == 'available',
                      onTap: () => setState(() => _taskFilter = 'available'),
                    ),
                    CategoryChip(
                      label: L.done,
                      active: _taskFilter == 'done',
                      onTap: () => setState(() => _taskFilter = 'done'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => state.refreshPlanner(),
                  child: tasks.isEmpty
                      ? ListView(children: [
                          EmptyState(
                            icon: Icons.task_alt_outlined,
                            title: L.myTasks,
                            sub: L.plannerEmpty,
                          ),
                        ])
                      : ListView.separated(
                          itemCount: tasks.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, index) =>
                              TaskBubbleCard(task: tasks[index]),
                        ),
                ),
              ),
            ]),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: state.chatChannels.length,
              itemBuilder: (_, i) {
                final channel = state.chatChannels[i];
                final unread = state.chatUnread[channel] ?? 0;
                final last = state.chatMessages(channel).firstOrNull;
                return AppCard(
                  index: i,
                  onTap: () {
                    state.openChatChannel(channel);
                    GoRouter.of(context).push('/chat');
                  },
                  child: Row(children: [
                    Avatar(
                        label: channelLabel(channel),
                        color: channelColor(channel)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(channelLabel(channel),
                                style: T.h3.copyWith(
                                    fontWeight: FontWeight.w700, fontSize: 16)),
                            Text(
                              last == null
                                  ? L.noMessages
                                  : '${last.authorName}: ${last.kind == 'task' && last.task != null ? last.task!.title : last.body}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  T.priceSmall.copyWith(color: AppTheme.ink2),
                            ),
                          ]),
                    ),
                    if (unread > 0)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.cta,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Text('$unread',
                            style: T.label.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800)),
                      ),
                  ]),
                );
              },
            ),
          ),
      ]),
    );
  }
}

class _TeamSegment extends StatelessWidget {
  const _TeamSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          constraints: const BoxConstraints(minHeight: 38),
          decoration: BoxDecoration(
            color: selected ? AppTheme.surfaceAlt : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon,
                size: 18, color: selected ? AppTheme.ink : AppTheme.ink3),
            const SizedBox(width: 7),
            Text(label,
                style: T.smallSemi
                    .copyWith(color: selected ? AppTheme.ink : AppTheme.ink2)),
          ]),
        ),
      );
}

class StaffChatScreen extends StatefulWidget {
  const StaffChatScreen({super.key});
  @override
  State<StaffChatScreen> createState() => _StaffChatScreenState();
}

class _StaffChatScreenState extends State<StaffChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final CafeState _state;
  late final String _channel;
  ChatMessageDto? _replyTo;
  bool _sending = false;
  List<String> _mentionCandidates = const [];

  @override
  void initState() {
    super.initState();
    _state = context.read<CafeState>();
    _channel = _state.activeChatChannel ?? 'general';
    _input.addListener(_onTyping);
  }

  @override
  void dispose() {
    _state.closeChatChannel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onTyping() {
    final text = _input.text;
    // Telegram-style: a lone "/" opens the command sheet.
    if (text == '/') {
      _input.clear();
      _showCommandSheet();
      return;
    }
    // "@" on the last token: offer name completion.
    final lastToken = text.split(' ').last;
    if (lastToken.startsWith('@')) {
      final needle = lastToken.substring(1).toLowerCase();
      final names = _knownNames()
          .where((name) => name.toLowerCase().startsWith(needle))
          .take(4)
          .toList();
      setState(() => _mentionCandidates = names);
    } else if (_mentionCandidates.isNotEmpty) {
      setState(() => _mentionCandidates = const []);
    }
  }

  List<String> _knownNames() {
    final names = <String>{};
    for (final employee in _state.staffAccounts) {
      names.add(employee.name);
    }
    for (final message in _state.chatMessages(_channel)) {
      if (!message.isBot) names.add(message.authorName);
    }
    names.remove(_state.activeUserName);
    return names.toList()..sort();
  }

  void _applyMention(String name) {
    final parts = _input.text.split(' ')..removeLast();
    // Mentions match by prefix server-side; the first word is enough and
    // keeps the input readable.
    parts.add('@${name.split(' ').first}');
    _input.text = '${parts.join(' ')} ';
    _input.selection =
        TextSelection.fromPosition(TextPosition(offset: _input.text.length));
    setState(() => _mentionCandidates = const []);
  }

  void _showCommandSheet() {
    final commands = [
      (L.cmdTaskHint, L.cmdTaskDesc, '/task '),
      (L.cmdRemindHint, L.cmdRemindDesc, '/remind '),
      ('/done', L.cmdDoneDesc, '/done'),
      ('/open', L.cmdOpenDesc, '/open'),
      ('/close', L.cmdCloseDesc, '/close'),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(L.commandsTitle, style: T.h2),
          const SizedBox(height: 10),
          for (final command in commands)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(command.$1,
                  style: T.bodySemi.copyWith(fontFamily: 'JetBrainsMono')),
              subtitle: Text(command.$2,
                  style: T.small.copyWith(color: AppTheme.ink2)),
              onTap: () {
                Navigator.pop(sheetContext);
                _input.text = command.$3;
                _input.selection = TextSelection.fromPosition(
                    TextPosition(offset: _input.text.length));
              },
            ),
        ]),
      ),
    );
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    final error = await _state.sendChat(
        channel: _channel, body: body, replyTo: _replyTo?.id);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (error == null) {
        _input.clear();
        _replyTo = null;
      }
    });
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppTheme.danger));
    }
  }

  void _openThread(ChatMessageDto parent) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChatThreadSheet(channel: _channel, parentId: parent.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final messages = state.chatMessages(_channel);
    final hasMore = state.chatHasMore[_channel] ?? false;

    return AppScaffold(
      bottomNav: null,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 8),
          child: Row(children: [
            IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back, color: AppTheme.ink)),
            Avatar(
                label: channelLabel(_channel), color: channelColor(_channel)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(channelLabel(_channel), style: T.screenTitle),
            ),
          ]),
        ),
        Expanded(
          child: state.chatLoading && messages.isEmpty
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : ListView.builder(
                  controller: _scroll,
                  reverse: true, // newest at the bottom, Telegram-style
                  itemCount: messages.length + (hasMore ? 1 : 0),
                  itemBuilder: (_, index) {
                    if (index >= messages.length) {
                      return Center(
                        child: TextButton(
                          onPressed: () => state.loadOlderChat(_channel),
                          child: Text(L.loadOlder,
                              style: T.smallSemi.copyWith(color: AppTheme.cta)),
                        ),
                      );
                    }
                    final message = messages[index];
                    return ChatBubble(
                      message: message,
                      own: !message.isBot &&
                          message.authorName == state.activeUserName,
                      onReply: () => setState(() => _replyTo = message),
                      onOpenThread: () => _openThread(message),
                    );
                  },
                ),
        ),
        if (_mentionCandidates.isNotEmpty)
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final name in _mentionCandidates)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      label: Text(name, style: T.smallSemi),
                      backgroundColor: AppTheme.card,
                      onPressed: () => _applyMention(name),
                    ),
                  ),
              ],
            ),
          ),
        if (_replyTo != null)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.separator),
            ),
            child: Row(children: [
              const Icon(Icons.reply, size: 16, color: AppTheme.cta),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${L.replyingTo} ${_replyTo!.authorName}: '
                  '${_replyTo!.kind == 'task' && _replyTo!.task != null ? _replyTo!.task!.title : _replyTo!.body}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.small.copyWith(color: AppTheme.ink2),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _replyTo = null),
                child: const Icon(Icons.close, size: 16, color: AppTheme.ink3),
              ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            IconButton(
              tooltip: L.commandsTitle,
              onPressed: _showCommandSheet,
              icon: const Icon(Icons.bolt_outlined, color: AppTheme.ink2),
            ),
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: L.message,
                  hintStyle: T.body.copyWith(color: AppTheme.ink3),
                  filled: true,
                  fillColor: AppTheme.card,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.espresso,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _sending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded,
                        size: 20, color: Colors.white),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// One message bubble: text, system/bot note, checklist header or live task.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.own,
    required this.onReply,
    required this.onOpenThread,
  });

  final ChatMessageDto message;
  final bool own;
  final VoidCallback onReply;
  final VoidCallback onOpenThread;

  String _time() {
    final created = message.createdAt == null
        ? null
        : DateTime.tryParse(message.createdAt!);
    if (created == null) return '';
    final local = created.toLocal();
    return '${local.hour}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (message.kind == 'task' && message.task != null) {
      return _wrap(
        context,
        TaskBubbleCard(task: message.task!),
      );
    }
    if (message.kind == 'system' || message.kind == 'checklist') {
      return _wrap(
        context,
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: message.kind == 'checklist'
                ? AppColors.gold.withValues(alpha: 0.12)
                : AppColors.sunken,
            borderRadius: BorderRadius.circular(14),
            border: message.kind == 'checklist'
                ? Border.all(color: AppColors.gold.withValues(alpha: 0.4))
                : null,
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('🤖 ${L.cafeBot}',
                style: T.label.copyWith(
                    color: AppTheme.ink2, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(message.body, style: T.body),
          ]),
        ),
      );
    }

    return _wrap(
      context,
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: own ? AppColors.espresso : AppTheme.card,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(own ? 16 : 5),
            bottomRight: Radius.circular(own ? 5 : 16),
          ),
          boxShadow: const [AppTheme.shadowCard],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!own)
              Text(message.authorName,
                  style: T.label.copyWith(
                      color: AppTheme.cta, fontWeight: FontWeight.w800)),
            if (message.replyPreview != null)
              Container(
                margin: const EdgeInsets.only(top: 3, bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: (own ? Colors.white : AppTheme.cta)
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border(
                    left: BorderSide(
                        color: own ? Colors.white : AppTheme.cta, width: 2),
                  ),
                ),
                child: Text(
                  '${message.replyPreview!.authorName}: ${message.replyPreview!.body}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: T.small
                      .copyWith(color: own ? Colors.white70 : AppTheme.ink2),
                ),
              ),
            Text(message.body,
                style:
                    T.body.copyWith(color: own ? Colors.white : AppTheme.ink)),
          ],
        ),
      ),
    );
  }

  Widget _wrap(BuildContext context, Widget bubble) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment:
            own ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () {
              HapticFeedback.selectionClick();
              onReply();
            },
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.82),
              child: bubble,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: onReply,
                  child: Text(L.replyAction,
                      style: T.label.copyWith(color: AppTheme.ink3)),
                ),
                if (message.replyCount > 0) ...[
                  Text('  ·  ', style: T.label.copyWith(color: AppTheme.ink3)),
                  GestureDetector(
                    onTap: onOpenThread,
                    child: Text(L.viewReplies(message.replyCount),
                        style: T.label.copyWith(
                            color: AppTheme.cta, fontWeight: FontWeight.w800)),
                  ),
                ],
                Text('  ${_time()}',
                    style: T.label.copyWith(color: AppTheme.ink3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The live task bubble: category chip, assignee, due, big Done checkbox —
/// the SAME object the planner shows; status syncs everywhere via WS.
class TaskBubbleCard extends StatelessWidget {
  const TaskBubbleCard({super.key, required this.task});
  final StaffTaskDto task;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final color = taskCategoryColor(task.category);
    final due = task.dueAt == null ? null : DateTime.tryParse(task.dueAt!);
    final overdue =
        task.isOpen && due != null && due.toLocal().isBefore(DateTime.now());
    final mine = task.assigneeId == state.activeEmployeeId;

    Future<void> toggle() async {
      final completing = !task.isDone;
      final error = await state.setTaskDone(task, completing);
      if (error != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error), backgroundColor: AppTheme.danger));
      } else if (completing && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L.t('Task completed', 'Attività completata')),
          action: SnackBarAction(
            label: L.t('Undo', 'Annulla'),
            onPressed: () => state.setTaskDone(task, false),
          ),
        ));
      }
    }

    Future<void> run(Future<String?> Function() action) async {
      final error = await action();
      if (error != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error), backgroundColor: AppTheme.danger));
      }
    }

    Future<void> leave() async {
      final error = await state.leaveTask(task);
      if (!context.mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppTheme.danger),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            L.t('Task returned to the team', 'Attività restituita al team')),
        action: SnackBarAction(
          label: L.t('Undo', 'Annulla'),
          onPressed: () => state.takeTask(task),
        ),
      ));
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: overdue ? AppTheme.danger : color.withValues(alpha: 0.45),
            width: 1.4),
        boxShadow: const [AppTheme.shadowCard],
      ),
      child: Row(children: [
        Semantics(
          button: true,
          label: task.isDone
              ? L.t('Reopen task', 'Riapri attività')
              : L.completeTask,
          child: InkWell(
            onTap: (mine || task.isDone) ? toggle : null,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: task.isDone ? AppColors.ok : AppTheme.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: task.isDone ? AppColors.ok : AppTheme.separator,
                    width: 1.5),
              ),
              child: task.isDone
                  ? const Icon(Icons.check, size: 20, color: Colors.white)
                  : mine
                      ? const Icon(Icons.circle_outlined,
                          size: 18, color: AppTheme.ink2)
                      : const Icon(Icons.lock_outline,
                          size: 17, color: AppTheme.ink3),
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              task.title,
              style: T.bodySemi.copyWith(
                decoration: task.isDone ? TextDecoration.lineThrough : null,
                color: task.isDone ? AppTheme.ink2 : AppTheme.ink,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(L.taskCategoryLabel(task.category),
                    style: T.label
                        .copyWith(color: color, fontWeight: FontWeight.w800)),
              ),
              Text(
                task.assigneeName.isEmpty ? L.anyoneOnShift : task.assigneeName,
                style: T.label.copyWith(color: AppTheme.ink2),
              ),
              if (due != null)
                Text(
                  L.dueAtShort(
                      '${due.toLocal().hour}:${due.toLocal().minute.toString().padLeft(2, '0')}'),
                  style: T.label.copyWith(
                      color: overdue ? AppTheme.danger : AppTheme.ink2,
                      fontWeight: overdue ? FontWeight.w800 : FontWeight.w600),
                ),
              if (overdue)
                Text(L.overdueTag,
                    style: T.label.copyWith(
                        color: AppTheme.danger, fontWeight: FontWeight.w900)),
              if (task.isDone && task.doneByName.isNotEmpty)
                Text(L.doneBy(task.doneByName),
                    style: T.label.copyWith(color: AppColors.ok)),
            ]),
          ]),
        ),
        if (task.isAvailable) ...[
          const SizedBox(width: 8),
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: () => run(() => state.takeTask(task)),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.cta,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(L.takeTask),
            ),
          ),
        ] else if (mine && task.isInProgress) ...[
          const SizedBox(width: 4),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(onPressed: toggle, child: Text(L.completeTask)),
              TextButton(onPressed: leave, child: Text(L.leaveTask)),
            ],
          ),
        ],
      ]),
    );
  }
}

/// A message's thread: the parent bubble + replies (oldest first) + a
/// composer that answers INTO the thread — where the bot's overdue nudge and
/// the assignee's "doing it now" live together.
class ChatThreadSheet extends StatefulWidget {
  const ChatThreadSheet(
      {super.key, required this.channel, required this.parentId});
  final String channel;
  final int parentId;

  @override
  State<ChatThreadSheet> createState() => _ChatThreadSheetState();
}

class _ChatThreadSheetState extends State<ChatThreadSheet> {
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send(CafeState state) async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    final error = await state.sendChat(
        channel: widget.channel, body: body, replyTo: widget.parentId);
    if (!mounted) return;
    setState(() => _sending = false);
    if (error == null) {
      _input.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppTheme.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final all = state.chatMessages(widget.channel);
    final parent = all.where((m) => m.id == widget.parentId).firstOrNull;
    final replies = all.where((m) => m.replyTo == widget.parentId).toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.78,
      decoration: const BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 14, 16, MediaQuery.viewInsetsOf(context).bottom + 14),
      child: Column(children: [
        Text(L.threadTitle, style: T.h2),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(children: [
            if (parent != null)
              ChatBubble(
                message: parent,
                own: false,
                onReply: () {},
                onOpenThread: () {},
              ),
            const Divider(height: 22),
            for (final reply in replies)
              ChatBubble(
                message: reply,
                own: !reply.isBot && reply.authorName == state.activeUserName,
                onReply: () {},
                onOpenThread: () {},
              ),
          ]),
        ),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(state),
              decoration: InputDecoration(
                hintText: L.message,
                filled: true,
                fillColor: AppTheme.card,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _send(state),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.espresso,
                borderRadius: BorderRadius.circular(13),
              ),
              child:
                  const Icon(Icons.send_rounded, size: 19, color: Colors.white),
            ),
          ),
        ]),
      ]),
    );
  }
}
