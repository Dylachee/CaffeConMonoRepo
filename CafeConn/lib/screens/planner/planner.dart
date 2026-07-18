import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/dtos.dart';
import '../../state/cafe_state.dart';
import '../../widgets/app_widgets.dart';
import '../chat/chat.dart';

/// The owner's day planner — a clean day journal over the SAME StaffTask
/// objects that live as chat bubbles. Manage capability sees everything
/// (Overdue / checklists / by category / Done) plus quick-add; everyone else
/// gets "My tasks" on the same route. Deliberately a list, not a kanban.
class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});
  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  final _quickAdd = TextEditingController();
  DateTime _day = DateTime.now();
  bool _showDone = false;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _quickAdd.dispose();
    super.dispose();
  }

  String get _dayIso =>
      '${_day.year.toString().padLeft(4, '0')}-${_day.month.toString().padLeft(2, '0')}-${_day.day.toString().padLeft(2, '0')}';

  bool get _isToday {
    final now = DateTime.now();
    return _day.year == now.year &&
        _day.month == now.month &&
        _day.day == now.day;
  }

  Future<void> _load() =>
      context.read<CafeState>().refreshPlanner(date: _dayIso).then((error) {
        if (error != null && mounted) _snack(error);
      });

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppTheme.danger));
  }

  void _shiftDay(int delta) {
    setState(() => _day = _day.add(Duration(days: delta)));
    _load();
  }

  Future<void> _submitQuickAdd() async {
    final input = _quickAdd.text.trim();
    if (input.isEmpty || _adding) return;
    setState(() => _adding = true);
    final error = await context.read<CafeState>().plannerQuickAdd(input);
    if (!mounted) return;
    setState(() => _adding = false);
    if (error != null) {
      _snack(error);
    } else {
      _quickAdd.clear();
    }
  }

  Future<void> _toggleDone(StaffTaskDto task) async {
    final error =
        await context.read<CafeState>().setTaskDone(task, !task.isDone);
    if (error != null && mounted) {
      _snack(error);
    } else {
      _load(); // buckets change (open -> done)
    }
  }

  void _openThread(StaffTaskDto task) async {
    final state = context.read<CafeState>();
    final thread = await state.fetchTaskThread(task.id);
    if (!mounted) return;
    final bubbleId = thread?.message?.id;
    if (bubbleId == null) return;
    // Threads render from the channel cache — make sure it's loaded.
    final channel = thread!.message!.channel;
    await state.openChatChannel(channel);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChatThreadSheet(channel: channel, parentId: bubbleId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final manage = state.capManage;
    final now = DateTime.now();

    var tasks = state.plannerTasks;
    if (!manage) {
      // "My tasks": mine or up-for-grabs, on the same route.
      tasks = tasks
          .where((t) =>
              t.assigneeName.isEmpty || t.assigneeName == state.activeUserName)
          .toList();
    }

    DateTime? dueOf(StaffTaskDto t) =>
        t.dueAt == null ? null : DateTime.tryParse(t.dueAt!)?.toLocal();
    final overdue = tasks
        .where((t) =>
            t.isOpen && _isToday && dueOf(t) != null && dueOf(t)!.isBefore(now))
        .toList();
    final done = tasks.where((t) => t.isDone).toList();
    final open = tasks.where((t) => t.isOpen && !overdue.contains(t)).toList();

    // Checklist progress bars (Opening 3/7) from the checklist provenance.
    final checklistGroups = <String, List<StaffTaskDto>>{};
    for (final task in tasks.where((t) => t.checklistKey.isNotEmpty)) {
      checklistGroups.putIfAbsent(task.checklistKey, () => []).add(task);
    }
    final byCategory = groupBy(open.where((t) => t.checklistKey.isEmpty),
        (StaffTaskDto t) => t.category);

    return AppScaffold(
      bottomNav: null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Header(
          title: manage ? L.planner : L.myTasks,
          subtitle: L.plannerSub,
          leading: Navigator.canPop(context)
              ? IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              : null,
          actions: [
            if (state.plannerLoading) const CupertinoActivityIndicator(),
          ],
        ),
        Row(children: [
          IconButton(
              onPressed: () => _shiftDay(-1),
              icon: const Icon(Icons.chevron_left, color: AppTheme.ink)),
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: _isToday
                    ? null
                    : () {
                        setState(() => _day = DateTime.now());
                        _load();
                      },
                child: Text(
                  _isToday ? L.today : _dayIso,
                  style: T.h3.copyWith(
                      fontWeight: FontWeight.w800,
                      color: _isToday ? AppTheme.ink : AppTheme.cta),
                ),
              ),
            ),
          ),
          IconButton(
              onPressed: () => _shiftDay(1),
              icon: const Icon(Icons.chevron_right, color: AppTheme.ink)),
        ]),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _quickAdd,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitQuickAdd(),
                decoration: InputDecoration(
                  hintText: L.quickAddHint,
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
              onTap: _submitQuickAdd,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.espresso,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _adding
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add, size: 22, color: Colors.white),
              ),
            ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (tasks.isEmpty && !state.plannerLoading)
                  EmptyState(
                      icon: Icons.event_available_outlined,
                      title: manage ? L.planner : L.myTasks,
                      sub: L.plannerEmpty),
                if (overdue.isNotEmpty) ...[
                  SectionTitle(L.sectionOverdue),
                  for (final task in overdue)
                    _PlannerRow(
                        task: task,
                        onToggle: () => _toggleDone(task),
                        onOpen: () => _openThread(task)),
                ],
                for (final entry in checklistGroups.entries) ...[
                  _ChecklistHeader(
                    label: L.checklistProgress(
                      entry.key == 'opening' ? L.catOpening : L.catClosing,
                      entry.value.where((t) => t.isDone).length,
                      entry.value.length,
                    ),
                    done: entry.value.where((t) => t.isDone).length,
                    total: entry.value.length,
                  ),
                  for (final task in entry.value.where((t) => t.isOpen))
                    _PlannerRow(
                        task: task,
                        onToggle: () => _toggleDone(task),
                        onOpen: () => _openThread(task)),
                ],
                for (final entry in byCategory.entries) ...[
                  SectionTitle(L.taskCategoryLabel(entry.key)),
                  for (final task in entry.value)
                    _PlannerRow(
                        task: task,
                        onToggle: () => _toggleDone(task),
                        onOpen: () => _openThread(task)),
                ],
                if (done.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 18, bottom: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _showDone = !_showDone),
                      child: Row(children: [
                        Text('${L.sectionDone} (${done.length})',
                            style: T.sectionTitle),
                        Icon(_showDone ? Icons.expand_less : Icons.expand_more,
                            size: 18, color: AppTheme.ink2),
                      ]),
                    ),
                  ),
                  if (_showDone)
                    for (final task in done)
                      _PlannerRow(
                          task: task,
                          onToggle: () => _toggleDone(task),
                          onOpen: () => _openThread(task)),
                ],
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

class _ChecklistHeader extends StatelessWidget {
  const _ChecklistHeader(
      {required this.label, required this.done, required this.total});
  final String label;
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : done / total;
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: T.sectionTitle),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: AppColors.sunken,
            valueColor: AlwaysStoppedAnimation(
                progress >= 1 ? AppColors.ok : AppTheme.cta),
          ),
        ),
      ]),
    );
  }
}

class _PlannerRow extends StatelessWidget {
  const _PlannerRow(
      {required this.task, required this.onToggle, required this.onOpen});
  final StaffTaskDto task;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final color = taskCategoryColor(task.category);
    final due = task.dueAt == null ? null : DateTime.tryParse(task.dueAt!);
    final mine = task.assigneeId == state.activeEmployeeId;

    Future<void> run(Future<String?> Function() action) async {
      final error = await action();
      if (error != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error), backgroundColor: AppTheme.danger));
      }
    }

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onTap: onOpen, // the task's chat thread — the whole story in one place
      child: Row(children: [
        GestureDetector(
          onTap: (mine || task.isDone) ? onToggle : null,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: task.isDone ? AppColors.ok : AppTheme.bg,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                  color: task.isDone ? AppColors.ok : AppTheme.separator,
                  width: 1.5),
            ),
            child: task.isDone
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : Icon(mine ? Icons.circle_outlined : Icons.lock_outline,
                    size: 17, color: AppTheme.ink3),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              task.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: T.bodySemi.copyWith(
                decoration: task.isDone ? TextDecoration.lineThrough : null,
                color: task.isDone ? AppTheme.ink2 : AppTheme.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              [
                task.assigneeName.isEmpty ? L.anyoneOnShift : task.assigneeName,
                if (due != null)
                  L.dueAtShort(
                      '${due.toLocal().hour}:${due.toLocal().minute.toString().padLeft(2, '0')}'),
                if (task.isDone && task.doneByName.isNotEmpty)
                  L.doneBy(task.doneByName),
              ].join(' · '),
              style: T.label.copyWith(color: AppTheme.ink2),
            ),
          ]),
        ),
        if (task.isAvailable)
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: () => run(() => state.takeTask(task)),
              child: Text(L.takeTask),
            ),
          )
        else if (mine && !task.isDone)
          SizedBox(
            height: 44,
            child: TextButton(
              onPressed: () => run(() => state.leaveTask(task)),
              child: Text(L.leaveTask),
            ),
          )
        else
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
      ]),
    );
  }
}
