import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

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
        const Header(title: 'Чаты', subtitle: 'Команда на связи'),
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
                      Avatar(label: group.name, color: zoneColor),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Row(children: [
                              Expanded(
                                  child: Text(group.name,
                                      style: T.h3.copyWith(fontWeight: FontWeight.w700, fontSize: 16))),
                              if (group.pinned)
                                const Icon(Icons.push_pin,
                                    size: 14, color: AppTheme.ink3)
                            ]),
                            Text(last?.text ?? 'Нет сообщений',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: T.priceSmall.copyWith(color: AppTheme.ink2)),
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

  @override
  void dispose() {
    input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
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

    _scrollToBottom();

    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return AppScaffold(
      child: Column(children: [
        Row(children: [
          IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back, color: AppTheme.ink)),
          Avatar(label: group.name, color: zoneColor),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(group.name,
                    style: T.h2.copyWith(fontSize: 17)),
                Text('${group.members.length} участников',
                    style: T.smallSemi),
              ])),
        ]),
        Expanded(
            child: messages.isEmpty
                ? EmptyState(
                    icon: Icons.chat_bubble_outline,
                    title: 'Чатик пуст',
                    sub: 'Начните общение — отправьте первое сообщение')
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 12),
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
                              .firstWhereOrNull(
                                  (u) => u.id == msg.senderId)
                              ?.name ??
                          msg.senderId;
                      return ChatBubble(
                          message: msg, senderName: senderName);
                    })),
        Padding(
          padding: EdgeInsets.only(
              bottom: keyboardInset > 0 ? keyboardInset + 8 : 8, top: 8),
          child: Row(children: [
            Expanded(
                child: AppTextField(controller: input, label: 'Сообщение...')),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                final text = input.text.trim();
                if (text.isEmpty) return;
                state.sendMessage(text);
                input.clear();
                _scrollToBottom();
              },
              child: const CircleAvatar(
                  radius: 25,
                  backgroundColor: AppTheme.cta,
                  child: Icon(Icons.send, color: Colors.white, size: 20)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class ChatBubble extends StatelessWidget {
  const ChatBubble(
      {super.key, required this.message, this.senderName = ''});
  final ChatMessage message;
  final String senderName;
  @override
  Widget build(BuildContext context) {
    final own = message.own;
    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            own ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!own && senderName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(senderName,
                  style: T.label),
            ),
          Container(
            constraints:
                BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: own ? AppTheme.cta : Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [AppTheme.shadowCard]),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(message.text,
                  style: T.body.copyWith(color: own ? Colors.white : AppTheme.ink)),
              const SizedBox(height: 4),
              Text(
                  '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                  style: T.label.copyWith(color: own ? Colors.white70 : AppTheme.ink3)),
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
    final order = state.orders
        .firstWhereOrNull((o) => o.id == message.refId);
    final table = order != null
        ? state.tables.firstWhereOrNull((t) => t.id == order.tableId)
        : null;
    final isKitchen = order?.splitTo == FeedType.kitchen;
    final zoneColor = isKitchen ? AppTheme.warning : AppTheme.bar;
    final zoneLabel = isKitchen ? 'Кухня' : 'Бар';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: zoneColor, width: 4)),
          boxShadow: const [AppTheme.shadowCard],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.receipt_long_outlined, size: 14),
            const SizedBox(width: 6),
            Text(
                'Новый заказ · Стол ${table?.number ?? '??'}',
                style: T.priceSmall.copyWith(color: zoneColor, fontWeight: FontWeight.w700)),
          ]),
          const Divider(height: 16),
          if (order != null)
            ...order.items.map((l) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Text('${l.quantity}×  ',
                        style: T.priceSmall.copyWith(fontWeight: FontWeight.w700)),
                    Expanded(
                        child: Text(l.item.name,
                            style: T.priceSmall)),
                    if (l.modifiers.isNotEmpty)
                      Text('(${l.modifiers})',
                          style: T.label.copyWith(color: AppTheme.ink2)),
                  ]),
                )),
          const Divider(height: 16),
          Text(
              '$zoneLabel · ${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
              style: T.label.copyWith(color: AppTheme.ink2)),
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
          Text('ПЕРЕСЛАНО · Елена',
              style: T.label.copyWith(color: AppTheme.tOccupied, fontWeight: FontWeight.w800))
        ]),
        const SizedBox(height: 8),
        Text('Стол${table?.number ?? '??'}',
            style: T.h2.copyWith(fontSize: 17)),
        const SizedBox(height: 4),
        Text(message.text,
            style: T.priceSmall.copyWith(color: AppTheme.ink2)),
        const Divider(height: 24),
        AppButton(
            label: 'Открыть стол',
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
