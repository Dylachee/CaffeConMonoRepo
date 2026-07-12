import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../state/cafe_state.dart';
import '../../widgets/app_widgets.dart';

class StaffChatListScreen extends StatelessWidget {
  const StaffChatListScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final groups = [...state.groups]
      ..sort((a, b) => b.pinned.toString().compareTo(a.pinned.toString()));
    return AppScaffold(
      bottomNav: null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Header(title: L.chats, subtitle: L.teamOnline, actions: [
          IconButton(
            tooltip: L.settings,
            icon: const Icon(Icons.settings_outlined, color: AppTheme.ink),
            onPressed: () => GoRouter.of(context).push('/settings'),
          ),
        ]),
        Expanded(
            child: ListView.builder(
                itemCount: groups.length,
                itemBuilder: (_, i) {
                  final group = groups[i];
                  final last = state.messages
                      .where((m) => m.groupId == group.id)
                      .lastOrNull;
                  final zoneColor = group.type == FeedType.kitchen
                      ? AppTheme.warning
                      : group.type == FeedType.bar
                          ? AppTheme.bar
                          : AppTheme.ink3;
                  return AppCard(
                    index: i,
                    onTap: () {
                      state.currentGroup = group;
                      GoRouter.of(context).push('/chat');
                    },
                    child: Row(children: [
                      Avatar(label: _groupDisplayName(group), color: zoneColor),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Row(children: [
                              Expanded(
                                  child: Text(_groupDisplayName(group),
                                      style: T.h3.copyWith(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16))),
                              if (group.pinned)
                                const Icon(Icons.push_pin,
                                    size: 14, color: AppTheme.ink3)
                            ]),
                            Text(last?.text ?? L.noMessages,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: T.priceSmall
                                    .copyWith(color: AppTheme.ink2)),
                          ])),
                      const SizedBox(width: 8),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                                last == null
                                    ? ''
                                    : '${last.timestamp.hour}:${last.timestamp.minute.toString().padLeft(2, '0')}',
                                style: T.label.copyWith(color: AppTheme.ink3)),
                          ]),
                    ]),
                  );
                })),
      ]),
    );
  }
}

class StaffChatScreen extends StatefulWidget {
  const StaffChatScreen({super.key});
  @override
  State<StaffChatScreen> createState() => _StaffChatScreenState();
}

class _StaffChatScreenState extends State<StaffChatScreen> {
  final input = TextEditingController();
  final _scrollController = ScrollController();
  String? _lastScrollKey;

  @override
  void dispose() {
    input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final target = _scrollController.position.maxScrollExtent;
        if (animated) {
          _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          );
        } else {
          _scrollController.jumpTo(target);
        }
      }
    });
  }

  void _scrollIfMessageSetChanged(String groupId, List<ChatMessage> messages) {
    final lastId = messages.isEmpty ? 'empty' : messages.last.id;
    final key = '$groupId:${messages.length}:$lastId';
    if (_lastScrollKey == key) return;
    final firstPaint =
        _lastScrollKey == null || !_lastScrollKey!.startsWith(groupId);
    _lastScrollKey = key;
    _scrollToBottom(animated: !firstPaint);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final group = state.currentGroup ?? state.groups.first;
    final messages =
        state.messages.where((m) => m.groupId == group.id).toList();
    final zoneColor = group.type == FeedType.kitchen
        ? AppTheme.warning
        : group.type == FeedType.bar
            ? AppTheme.bar
            : AppTheme.ink3;

    _scrollIfMessageSetChanged(group.id, messages);

    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return AppScaffold(
      child: Column(children: [
        _ChatHeader(
          group: group,
          color: zoneColor,
          onBack: () => context.pop(),
        ),
        Expanded(
            child: messages.isEmpty
                ? EmptyState(
                    icon: Icons.chat_bubble_outline,
                    title: L.chatEmpty,
                    sub: L.startConversation)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(2, 14, 2, 18),
                    itemCount: messages.length,
                    itemBuilder: (ctx, i) {
                      final msg = messages[i];
                      if (msg.kind == MessageKind.tableCard) {
                        return ForwardedTableCard(message: msg);
                      }
                      if (msg.kind == MessageKind.orderCard) {
                        return OrderReceiptCard(message: msg);
                      }
                      final senderName = state.staff
                              .firstWhereOrNull((u) => u.id == msg.senderId)
                              ?.name ??
                          msg.senderId;
                      return ChatBubble(message: msg, senderName: senderName);
                    })),
        Padding(
          padding: EdgeInsets.only(
              bottom: keyboardInset > 0 ? keyboardInset + 8 : 8, top: 8),
          child: Row(children: [
            Expanded(child: AppTextField(controller: input, label: L.message)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                final text = input.text.trim();
                if (text.isEmpty) return;
                state.sendMessage(text);
                input.clear();
                _scrollToBottom();
              },
              child: Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: AppTheme.cta,
                  shape: BoxShape.circle,
                  boxShadow: [AppTheme.shadowCard],
                ),
                child: const Icon(Icons.send_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.group,
    required this.color,
    required this.onBack,
  });

  final ChatGroup group;
  final Color color;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [AppTheme.shadowCard],
      ),
      child: Row(children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.ink),
        ),
        Avatar(label: _groupDisplayName(group), color: color),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_groupDisplayName(group),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.h2.copyWith(fontSize: 17)),
            const SizedBox(height: 2),
            Text(L.membersCount(group.members.length), style: T.smallSemi),
          ]),
        ),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ]),
    );
  }
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.message, this.senderName = ''});
  final ChatMessage message;
  final String senderName;
  @override
  Widget build(BuildContext context) {
    final own = message.own;
    final bubbleColor = own ? AppTheme.cta : AppTheme.card;
    final textColor = own ? Colors.white : AppTheme.ink;
    final timeColor = own ? Colors.white70 : AppTheme.ink3;
    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            own ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!own && senderName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(senderName, style: T.label),
            ),
          Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * .76),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(13, 10, 13, 8),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(own ? 16 : 5),
                bottomRight: Radius.circular(own ? 5 : 16),
              ),
              boxShadow: const [AppTheme.shadowCard],
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(message.text,
                  style: T.body.copyWith(color: textColor, height: 1.28)),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                    '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                    style: T.label.copyWith(color: timeColor)),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class OrderReceiptCard extends StatelessWidget {
  const OrderReceiptCard({super.key, required this.message});
  final ChatMessage message;
  @override
  Widget build(BuildContext context) {
    final state = context.read<CafeState>();
    final order = state.orders.firstWhereOrNull((o) => o.id == message.refId);
    final table = order != null
        ? state.tables.firstWhereOrNull((t) => t.id == order.tableId)
        : null;
    final isKitchen = order?.splitTo == FeedType.kitchen;
    final zoneColor = isKitchen ? AppTheme.warning : AppTheme.bar;
    final zoneLabel = isKitchen ? L.kitchen : L.bar;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [AppTheme.shadowCard],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(height: 4, color: zoneColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 11, 13, 0),
            child: Row(children: [
              Icon(Icons.receipt_long_outlined, size: 16, color: zoneColor),
              const SizedBox(width: 7),
              Expanded(
                child: Text(L.newOrderTable(table?.number ?? '??'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.priceSmall.copyWith(
                        color: zoneColor, fontWeight: FontWeight.w800)),
              ),
              Text(
                  '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                  style: T.label.copyWith(color: AppTheme.ink3)),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 13),
            child: Divider(height: 16),
          ),
          if (order != null)
            ...order.items.map((l) => Padding(
                  padding: const EdgeInsets.fromLTRB(13, 0, 13, 5),
                  child: Row(children: [
                    SizedBox(
                      width: 34,
                      child: Text('${l.quantity}×',
                          style: T.priceSmall
                              .copyWith(fontWeight: FontWeight.w800)),
                    ),
                    Expanded(
                        child: Text(l.item.displayName, style: T.priceSmall)),
                    if (l.modifiers.isNotEmpty)
                      Text('(${l.modifiers})',
                          style: T.label.copyWith(color: AppTheme.ink2)),
                  ]),
                )),
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 6, 13, 12),
            child: Text(zoneLabel,
                style: T.label
                    .copyWith(color: zoneColor, fontWeight: FontWeight.w900)),
          ),
        ]),
      ),
    );
  }
}

class ForwardedTableCard extends StatelessWidget {
  const ForwardedTableCard({super.key, required this.message});
  final ChatMessage message;
  @override
  Widget build(BuildContext context) {
    final state = context.read<CafeState>();
    final table = state.tables.firstWhereOrNull((t) => t.id == message.refId);
    return AppCard(
      borderColor: AppTheme.tOccupied,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.forward, size: 14, color: AppTheme.tOccupied),
          const SizedBox(width: 8),
          Text(L.forwarded,
              style: T.label.copyWith(
                  color: AppTheme.tOccupied, fontWeight: FontWeight.w800))
        ]),
        const SizedBox(height: 8),
        Text(L.tableN(table?.number ?? '??'),
            style: T.h2.copyWith(fontSize: 17)),
        const SizedBox(height: 4),
        Text(message.text, style: T.priceSmall.copyWith(color: AppTheme.ink2)),
        const Divider(height: 24),
        AppButton(
            label: L.openTable,
            kind: ButtonKind.ghost,
            onPressed: () {
              if (table != null) {
                state.currentTable = table;
                GoRouter.of(context).push('/table-details');
              }
            })
      ]),
    );
  }
}

String _groupDisplayName(ChatGroup group) => switch (group.type) {
      FeedType.kitchen => L.kitchen,
      FeedType.bar => L.bar,
      _ => L.generalChat,
    };
