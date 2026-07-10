import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../models/models.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/api_config.dart';
import '../../state/cafe_state.dart';
import '../../widgets/app_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        leading: const BackButton(),
        title: Text(L.settings, style: T.h2),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SettingsSection(L.account, [
            _SettingsRow(label: L.currentStaff, value: state.activeUserName),
            if (state.backendConnected)
              _SettingsRow(label: L.role, value: roleLabel(state.currentRole)),
            if (state.backendConnected)
              _SettingsRow(
                label: L.logout,
                trailing: const Icon(Icons.logout, color: AppTheme.danger),
                onTap: () => _confirmLogout(context, state),
              ),
          ]),
          _SettingsSection(L.appearance, [
            // EN/IT toggle: flips every label in the app and the menu
            // content (names/descriptions come bilingual from the hub).
            _SettingsSegmented(
              label: L.language,
              options: const ['English', 'Italiano'],
              selected: state.appLang.index,
              onChanged: (i) => state.setLanguage(AppLang.values[i]),
            ),
            _SettingsSegmented(
              label: L.theme,
              options: [L.themeLight, L.themeDark, L.themeSystem],
              selected: state.themeMode.index,
              onChanged: (i) => state.setSetting(
                  'theme', i, (v) => state.themeMode = ThemeMode.values[v]),
            ),
            _SettingsSegmented(
              label: L.textSize,
              options: [L.sizeSmall, L.sizeNormal, L.sizeLarge],
              selected: state.textScale == 0.85
                  ? 0
                  : state.textScale == 1.15
                      ? 2
                      : 1,
              onChanged: (i) {
                final scales = [0.85, 1.0, 1.15];
                state.setSetting(
                    'textScale', scales[i], (v) => state.textScale = v);
              },
            ),
          ]),
          _SettingsSection(L.display, [
            _SettingsSegmented(
              label: L.tablesPerRow,
              options: const ['3', '4'],
              selected: state.tablesPerRow == 3 ? 0 : 1,
              onChanged: (i) => state.setSetting('tablesPerRow', i == 0 ? 3 : 4,
                  (v) => state.tablesPerRow = v),
            ),
            _SettingsToggle(
                label: L.gestureHints,
                value: state.showGestureHints,
                onChanged: (v) => state.setSetting(
                    'showGestureHints', v, (x) => state.showGestureHints = x)),
            _SettingsToggle(
                label: L.hour24,
                value: state.use24hClock,
                onChanged: (v) => state.setSetting(
                    'use24hClock', v, (x) => state.use24hClock = x)),
          ]),
          _SettingsSection(L.hapticsSound, [
            _SettingsToggle(
                label: L.haptics,
                value: state.hapticsEnabled,
                onChanged: (v) => state.setSetting(
                    'hapticsEnabled', v, (x) => state.hapticsEnabled = x)),
            _SettingsToggle(
                label: L.sounds,
                value: state.soundEnabled,
                onChanged: (v) => state.setSetting(
                    'soundEnabled', v, (x) => state.soundEnabled = x)),
          ]),
          _SettingsSection(L.connection, [
            _SettingsRow(
                label: L.statusLbl,
                value: state.backendConnecting
                    ? L.connectingS
                    : state.backendConnected
                        ? L.connected
                        : L.localMode),
            _SettingsRow(label: L.server, value: ApiConfig.baseUrl),
            if (state.backendError != null)
              _SettingsRow(label: L.lastError, value: state.backendError),
            // Below: two different ways to (re)establish the connection.
            // reconnect() only works once _lastUser/_lastPass are already set
            // from a prior successful login (or via --dart-define, which we
            // deliberately do not bake into the web build — that would ship
            // real staff passwords inside a publicly downloadable JS bundle).
            // So the very first connection on a fresh device must go through
            // a typed login, not "Reconnect" — hence this form.
            if (!state.backendConnected) const _ConnectionLoginForm(),
            if (state.backendConnected)
              _SettingsRow(
                  label: L.reconnect,
                  trailing: state.backendConnecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.cta))
                      : const Icon(Icons.sync, color: AppTheme.cta),
                  onTap:
                      state.backendConnecting ? null : () => state.reconnect()),
          ]),
          _SettingsSection(L.dataSync, [
            _SettingsToggle(
                label: L.simulateOffline,
                value: state.offlineModeSimulated,
                onChanged: (v) {
                  state.setSetting('offlineModeSimulated', v,
                      (x) => state.offlineModeSimulated = x);
                  state.online = !v;
                  state.refresh();
                }),
            _SettingsRow(
                label: L.pendingUpload,
                value: L.actionsCount(state.pendingQueueCount)),
            _SettingsRow(
                label: L.resetDemo,
                trailing: const Icon(Icons.restart_alt, color: AppTheme.danger),
                onTap: () => _confirmResetToDemo(context, state)),
          ]),
          _SettingsSection(L.aboutApp, [
            _SettingsRow(label: L.version, value: 'v0.2.0'),
          ]),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, CafeState state) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(L.logout),
        content: Text(L.logoutConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(L.cancel)),
          TextButton(
              onPressed: () async {
                Navigator.pop(c);
                await state.disconnectBackend();
                // Back on the settings screen the login form now shows; pop
                // to the shell so the (now local/demo) app is usable again.
                if (context.mounted) Navigator.of(context).maybePop();
              },
              child: Text(L.logout, style: T.bodySemi)),
        ],
      ),
    );
  }

  void _confirmResetToDemo(BuildContext context, CafeState state) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(L.resetData),
        content: Text(L.resetWarn),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(L.cancel)),
          TextButton(
              onPressed: () {
                state.resetToDemo();
                Navigator.pop(c);
              },
              child: Text(L.reset, style: T.bodySemi)),
        ],
      ),
    );
  }
}

// First-time login form for the "Connection" settings section. Distinct from
// reconnect() (which only re-uses credentials from an already-successful
// session): this is the only in-app way to type a username/password, since
// the web build intentionally does not bake real staff passwords into the
// public JS bundle via --dart-define.
class _ConnectionLoginForm extends StatefulWidget {
  const _ConnectionLoginForm();
  @override
  State<_ConnectionLoginForm> createState() => _ConnectionLoginFormState();
}

class _ConnectionLoginFormState extends State<_ConnectionLoginForm> {
  final _username = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit(CafeState state) async {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) return;
    FocusScope.of(context).unfocus();
    await state.connectBackend(username: username, password: password);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CafeState>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppTextField(controller: _username, label: L.login),
        const SizedBox(height: 10),
        AppTextField(controller: _password, label: L.password, obscure: true),
        const SizedBox(height: 12),
        PrimaryButton(
          label: state.backendConnecting ? L.connectingS : L.signIn,
          onTap: state.backendConnecting ? null : () => _submit(state),
          height: 46,
        ),
      ]),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsSection(this.title, this.children);
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
              padding: const EdgeInsets.only(left: 12, top: 24, bottom: 8),
              child: Text(title.toUpperCase(),
                  style: T.label.copyWith(color: AppTheme.ink3))),
          AppCard(padding: EdgeInsets.zero, child: Column(children: children)),
        ],
      );
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _SettingsRow(
      {required this.label, this.value, this.trailing, this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(label, style: T.h3.copyWith(fontWeight: FontWeight.w500)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (value != null)
            // Bug fix: an unconstrained long value (e.g. backendError's full
            // sentence) took its full intrinsic width in ListTile.trailing,
            // squeezing the title down to ~0px and wrapping it one letter per
            // line. Capping width + wrapping onto up to 2 lines keeps long
            // values (error text) readable without starving the label.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(
                value!,
                style: T.body.copyWith(color: AppTheme.ink2),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          if (trailing != null) trailing!,
        ]),
        onTap: onTap,
      );
}

class _SettingsToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SettingsToggle(
      {required this.label, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => SwitchListTile(
        title: Text(label, style: T.h3.copyWith(fontWeight: FontWeight.w500)),
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppTheme.cta,
      );
}

class _SettingsSegmented extends StatelessWidget {
  final String label;
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;
  const _SettingsSegmented(
      {required this.label,
      required this.options,
      required this.selected,
      required this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: T.h3.copyWith(fontWeight: FontWeight.w500))),
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                  color: AppTheme.surfaceSunken,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(
                  children: List.generate(
                      options.length,
                      (i) => GestureDetector(
                            onTap: () => onChanged(i),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                  color: selected == i
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: selected == i
                                      ? [
                                          const BoxShadow(
                                              color: Colors.black12,
                                              blurRadius: 4)
                                        ]
                                      : null),
                              child: Text(options[i],
                                  style: T.priceSmall.copyWith(
                                      fontWeight: selected == i
                                          ? FontWeight.w600
                                          : FontWeight.w400)),
                            ),
                          ))),
            ),
          ],
        ),
      );
}
