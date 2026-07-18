import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme/app_theme.dart';
import '../../data/dtos.dart';
import '../../state/cafe_state.dart';
import '../../widgets/app_widgets.dart';

/// Feed manager: paste a post URL, see the list (pinned first, exactly the
/// hub's order), pin/unpin, hide/delete. Every backend error (invalid link,
/// pinned limit 409, network) is shown to the user verbatim in a snackbar.
class FeedManagerScreen extends StatefulWidget {
  const FeedManagerScreen({super.key});
  @override
  State<FeedManagerScreen> createState() => _FeedManagerScreenState();
}

class _FeedManagerScreenState extends State<FeedManagerScreen> {
  final _urlController = TextEditingController();
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<CafeState>().refreshContentFeed());
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message), backgroundColor: AppTheme.danger));
  }

  Future<void> _addPost() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || _adding) return;
    setState(() => _adding = true);
    final err = await context.read<CafeState>().addFeedPost(url);
    if (!mounted) return;
    setState(() => _adding = false);
    if (err != null) {
      _showError(err);
      return;
    }
    _urlController.clear();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L.postAdded), backgroundColor: AppTheme.success));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    final posts = state.feedPosts;

    return RefreshIndicator(
      onRefresh: () => context.read<CafeState>().refreshContentFeed(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppTextField(
                controller: _urlController,
                label: L.pasteSocialUrl,
                hint: 'https://…',
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: L.addPost,
                icon: Icons.add_link,
                enabled: !_adding,
                onTap: _adding ? null : _addPost,
              ),
            ]),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: SectionTitle(L.feedTab)),
            if (state.feedLoading)
              const CupertinoActivityIndicator()
            else
              Text(L.pinnedOfLimit(state.pinnedPostCount, state.feedPinnedLimit),
                  style: T.smallSemi.copyWith(color: AppTheme.ink2)),
          ]),
          if (posts.isEmpty && !state.feedLoading)
            EmptyState(
                icon: Icons.dynamic_feed_outlined,
                title: L.feedEmptyTitle,
                sub: L.feedEmptySub)
          else
            ...posts.map((post) => _FeedPostCard(post: post, onError: _showError)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Brand color + short label per platform (Material has no brand icons).
(Color, String, String) platformBadge(String platform) => switch (platform) {
      'instagram' => (const Color(0xFFC13584), 'IG', 'Instagram'),
      'threads' => (const Color(0xFF1E1B16), 'Th', 'Threads'),
      'twitter_x' => (const Color(0xFF14171A), 'X', 'X (Twitter)'),
      'facebook' => (const Color(0xFF1877F2), 'f', 'Facebook'),
      _ => (AppTheme.ink2, '?', platform),
    };

class _FeedPostCard extends StatelessWidget {
  const _FeedPostCard({required this.post, required this.onError});
  final SocialPostDto post;
  final ValueChanged<String> onError;

  Future<void> _run(Future<String?> action) async {
    final err = await action;
    if (err != null) onError(err);
  }

  void _confirmDelete(BuildContext context) {
    final state = context.read<CafeState>();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L.deletePostQ),
        content: Text(L.deletePostWarn),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(L.cancel)),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _run(state.deleteFeedPost(post));
            },
            child: Text(L.yesDelete,
                style: const TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<CafeState>();
    final (color, initials, label) = platformBadge(post.platform);

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(13)),
            child: Center(
                child: Text(initials,
                    style: T.h3.copyWith(color: color, fontWeight: FontWeight.w800))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$label · ${post.domain}',
                  style: T.bodySemi, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(post.sourceUrl,
                  style: T.small, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (post.isPinned) _Tag(label: L.pinnedLabel, color: AppTheme.gold),
          if (post.isHidden) ...[
            const SizedBox(width: 6),
            _Tag(label: L.hiddenLabel, color: AppTheme.ink2),
          ],
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _ActionChip(
            icon: post.isPinned
                ? Icons.push_pin
                : Icons.push_pin_outlined,
            label: post.isPinned ? L.unpinAction : L.pinAction,
            onTap: () =>
                _run(state.setFeedPostPinned(post, !post.isPinned)),
          ),
          const SizedBox(width: 8),
          _ActionChip(
            icon: post.isHidden
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            label: post.isHidden ? L.unhideAction : L.hideAction,
            onTap: () => _run(state.toggleFeedPostHidden(post)),
          ),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: L.copyLink,
            icon: const Icon(Icons.copy_rounded, size: 18, color: AppTheme.ink2),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: post.sourceUrl));
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(L.linkCopied)));
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: L.deletePost,
            icon: const Icon(Icons.delete_outline,
                size: 18, color: AppTheme.danger),
            onPressed: () => _confirmDelete(context),
          ),
        ]),
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8)),
        child: Text(label,
            style: T.label.copyWith(color: color, fontWeight: FontWeight.w800)),
      );
}

class _ActionChip extends StatelessWidget {
  const _ActionChip(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: AppTheme.bg,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: AppTheme.separator),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: AppTheme.ink),
            const SizedBox(width: 6),
            Text(label,
                style: T.smallSemi.copyWith(color: AppTheme.ink)),
          ]),
        ),
      );
}
