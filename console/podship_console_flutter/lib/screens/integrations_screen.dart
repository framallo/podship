import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:intl/intl.dart';
import 'package:podship_console_client/podship_console_client.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:serverpod_auth_idp_flutter/serverpod_auth_idp_flutter.dart';

import '../client.dart';
import '../l10n/gen/app_localizations.dart';
import '../theme.dart';

/// `/settings/integrations` (podship-design `specs/integrations.md`, INT).
class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  Me? _me;
  List<IntegrationView> _views = const [];
  Object? _loadError;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  IntegrationView? _view(IntegrationProvider p) =>
      _views.where((v) => v.provider == p).firstOrNull;

  Future<void> _load() async {
    try {
      final me = await client.me.get();
      final views = await client.integrations.list();
      if (!mounted) return;
      final wasPending = _view(IntegrationProvider.aws)?.status == 'pending';
      setState(() {
        _me = me;
        _views = views;
        _loadError = null;
      });
      final aws = _view(IntegrationProvider.aws);
      if (wasPending && aws?.status == 'connected') {
        _announce(AppLocalizations.of(context).intConnectedNow('AWS'));
      }
      // INT-14: the card updates by itself while AWS is pending.
      if (aws?.status == 'pending') {
        _poll ??= Timer.periodic(const Duration(seconds: 5), (_) => _load());
      } else {
        _poll?.cancel();
        _poll = null;
      }
    } on Object catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  void _replace(IntegrationView v) => setState(() {
    _views = [
      for (final x in _views)
        if (x.provider == v.provider) v else x,
    ];
  });

  void _announce(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    SemanticsService.sendAnnouncement(
      View.of(context),
      text,
      Directionality.of(context),
    );
  }

  Future<void> _startAws() async {
    final l = AppLocalizations.of(context);
    try {
      final start = await client.integrations.startAws();
      await launchUrl(
        Uri.parse(start.consoleUrl),
        webOnlyWindowName: '_blank',
      );
    } on IntegrationException catch (e) {
      if (mounted) {
        _announce(
          e.reason == IntegrationFailure.notReady
              ? l.intAwsNotReady
              : l.commonError,
        );
      }
    }
    await _load();
  }

  Future<void> _disconnect(IntegrationProvider p) async {
    final l = AppLocalizations.of(context);
    final name = p == IntegrationProvider.cloudflare ? 'Cloudflare' : 'AWS';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.intDisconnectTitle(name)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Text(
            p == IntegrationProvider.cloudflare
                ? l.intDisconnectCf(_me?.workspaceName ?? '')
                : l.intDisconnectAws(_me?.workspaceName ?? ''),
          ),
        ),
        actions: [
          OutlinedButton(
            autofocus: true,
            onPressed: () => Navigator.pop(c, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.ps.danger,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: Text(l.intDisconnectConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final v = await client.integrations.disconnect(p);
    _replace(v);
    if (!mounted) return;
    _announce(l.intDisconnected(name));
    // INT-17: what the person does at the provider.
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.intDisconnected(name)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p == IntegrationProvider.cloudflare
                    ? l.intCfRevokeHint
                    : l.intAwsRevokeHint,
              ),
              const SizedBox(height: 8),
              _NewTabLink(
                label: p == IntegrationProvider.cloudflare
                    ? l.intCfRevokeLink
                    : l.intAwsRevokeLink,
                url: p == IntegrationProvider.cloudflare
                    ? 'https://dash.cloudflare.com/profile/api-tokens'
                    : 'https://console.aws.amazon.com/cloudformation/home#/stacks',
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    final me = _me;
    Widget body;
    if (me == null && _loadError == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (me == null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.commonError),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _load, child: Text(l.commonRetry)),
          ],
        ),
      );
    } else {
      final cards = [
        _CloudflareCard(
          view: _view(IntegrationProvider.cloudflare),
          canManage: me.canManage,
          onChanged: (v) {
            _replace(v);
            if (v.status == 'connected') {
              _announce(l.intConnectedNow('Cloudflare'));
            }
          },
          onDisconnect: () => _disconnect(IntegrationProvider.cloudflare),
          onRetry: () async => _replace(
            await client.integrations.check(IntegrationProvider.cloudflare),
          ),
        ),
        _AwsCard(
          view: _view(IntegrationProvider.aws),
          canManage: me.canManage,
          onConnect: _startAws,
          onDisconnect: () => _disconnect(IntegrationProvider.aws),
          onRetry: () async => _replace(
            await client.integrations.check(IntegrationProvider.aws),
          ),
        ),
      ];
      body = SingleChildScrollView(
        padding: EdgeInsets.all(wide ? 32 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                l.intTitle,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l.intLead(me.workspaceName),
              style: TextStyle(color: context.ps.ink2),
            ),
            if (!me.canManage) ...[
              const SizedBox(height: 16),
              _Banner(
                icon: Icons.info_outline,
                text: l.intOnlyAdmins,
                color: context.ps.container,
              ),
            ],
            const SizedBox(height: 24),
            if (wide)
              Wrap(
                spacing: 24,
                runSpacing: 24,
                children: [
                  for (final c in cards) SizedBox(width: 480, child: c),
                ],
              )
            else
              Column(
                children: [
                  for (final c in cards) ...[c, const SizedBox(height: 16)],
                ],
              ),
          ],
        ),
      );
    }
    final signOut = TextButton(
      onPressed: () => client.auth.signOutDevice(),
      child: Text(l.signOut),
    );
    if (!wide) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l.settingsIntegrations),
          actions: [signOut],
        ),
        body: body,
      );
    }
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 240,
            color: context.ps.container,
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.anchor,
                          size: 14,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'podship',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Material(
                  color: context.ps.surface,
                  borderRadius: BorderRadius.circular(6),
                  child: ListTile(
                    selected: true,
                    dense: true,
                    leading: const Icon(Icons.settings_outlined, size: 20),
                    title: Text(l.navSettings),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: context.ps.hairline),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${me?.workspaceName ?? ''} / ${l.navSettings} / ',
                        style: TextStyle(color: context.ps.ink2),
                      ),
                      Text(
                        l.settingsIntegrations,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      if (me != null)
                        Text(
                          me.email,
                          style: TextStyle(color: context.ps.ink2),
                        ),
                      const SizedBox(width: 8),
                      signOut,
                    ],
                  ),
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Pieces -----------------------------------------------------------------

String _date(BuildContext context, DateTime? d) => d == null
    ? ''
    : DateFormat.yMMMd(
        Localizations.localeOf(context).toLanguageTag(),
      ).format(d.toLocal());

String _time(BuildContext context, DateTime? d) => d == null
    ? ''
    : DateFormat.Hm(
        Localizations.localeOf(context).toLanguageTag(),
      ).format(d.toLocal());

/// INT-21: an icon and a word, never color only.
class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status);
  final String status;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (icon, text, fg, bg) = switch (status) {
      'connected' => (
        Icons.check_circle_outline,
        l.intStatusOn,
        context.ps.ok,
        context.ps.okC,
      ),
      'pending' => (
        Icons.hourglass_top,
        l.intStatusWaiting,
        context.ps.run,
        context.ps.runC,
      ),
      _ => (
        Icons.circle_outlined,
        l.intStatusOff,
        context.ps.ink2,
        context.ps.container,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: fg, fontSize: 13)),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _NewTabLink extends StatelessWidget {
  const _NewTabLink({required this.label, required this.url});
  final String label;
  final String url;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Semantics(
      link: true,
      label: '$label ${l.commonNewTab}',
      excludeSemantics: true,
      child: TextButton.icon(
        style: TextButton.styleFrom(padding: EdgeInsets.zero),
        onPressed: () => launchUrl(Uri.parse(url), webOnlyWindowName: '_blank'),
        icon: const Icon(Icons.open_in_new, size: 16),
        label: Text(label),
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts(this.rows);
  final List<(String, Widget)> rows;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (k, v) in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(k, style: TextStyle(color: context.ps.ink2)),
              ),
              Expanded(child: v),
            ],
          ),
        ),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.icon,
    required this.status,
    required this.children,
  });
  final String title;
  final IconData icon;
  final String status;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              _StatusPill(status),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}

class _Permissions extends StatelessWidget {
  const _Permissions(this.lines);
  final List<String> lines;
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(
        AppLocalizations.of(context).intPermissions,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      children: [
        for (final s in lines)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $s',
                style: TextStyle(fontSize: 12, color: context.ps.ink2),
              ),
            ),
          ),
      ],
    ),
  );
}

Widget _checkFailed(
  BuildContext context,
  String provider,
  IntegrationView v,
) {
  if (v.lastCheckOk != false) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _Banner(
      icon: Icons.warning_amber,
      text: AppLocalizations.of(
        context,
      ).intCheckFailed(provider, _time(context, v.lastCheckAt)),
      color: context.ps.warnC,
    ),
  );
}

// --- Cloudflare ---------------------------------------------------------------

class _CloudflareCard extends StatefulWidget {
  const _CloudflareCard({
    required this.view,
    required this.canManage,
    required this.onChanged,
    required this.onDisconnect,
    required this.onRetry,
  });
  final IntegrationView? view;
  final bool canManage;
  final ValueChanged<IntegrationView> onChanged;
  final VoidCallback onDisconnect;
  final Future<void> Function() onRetry;

  @override
  State<_CloudflareCard> createState() => _CloudflareCardState();
}

class _CloudflareCardState extends State<_CloudflareCard> {
  final _token = TextEditingController();
  bool _pasting = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final url = await client.integrations.cloudflareTokenUrl();
    setState(() => _pasting = true);
    await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
  }

  String _permissionText(AppLocalizations l, String? p) {
    final es = l.localeName.startsWith('es');
    return switch (p) {
      'zone:read' => es ? 'leer tus zonas' : 'read your zones',
      'dns:edit' => es ? 'editar DNS' : 'edit DNS',
      'argotunnel:edit' =>
        es ? 'editar Cloudflare Tunnel' : 'edit Cloudflare Tunnel',
      'access:edit' => es ? 'editar Access' : 'edit Access',
      _ => p ?? '',
    };
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    if (_token.text.trim().isEmpty) {
      setState(() => _error = l.intCfEmpty);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final v = await client.integrations.saveCloudflare(_token.text);
      _token.clear();
      setState(() => _pasting = false);
      widget.onChanged(v);
    } on IntegrationException catch (e) {
      setState(
        () => _error = switch (e.reason) {
          IntegrationFailure.empty => l.intCfEmpty,
          IntegrationFailure.inactive => l.intCfInactive,
          IntegrationFailure.invalid => l.intCfInvalid,
          IntegrationFailure.missingPermission => l.intCfMissing(
            _permissionText(l, e.detail),
          ),
          IntegrationFailure.forbidden => l.intOnlyAdmins,
          IntegrationFailure.unreachable ||
          IntegrationFailure.notReady => l.commonError,
        },
      );
    } on Object {
      setState(() => _error = l.commonError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final v = widget.view;
    final connected = v?.status == 'connected';
    final perms = _Permissions([l.intCfPerm1, l.intCfPerm2]);
    return _Card(
      title: 'Cloudflare',
      icon: Icons.cloud_outlined,
      status: v?.status ?? 'off',
      children: [
        Text(l.intCfWhat),
        const SizedBox(height: 12),
        if (connected) ...[
          _checkFailed(context, 'Cloudflare', v!),
          _Facts([
            (
              l.intAwsAccount,
              Text(l.intCfAccount(v.account ?? '', v.zones ?? 0)),
            ),
            (
              l.intToken,
              Text(l.intTokenEnds(v.hint ?? ''), style: mono(context)),
            ),
            (
              l.intConnectedLabel,
              Text(
                l.intConnectedBy(
                  v.connectedBy ?? '',
                  _date(context, v.connectedAt),
                ),
              ),
            ),
          ]),
          perms,
          if (widget.canManage)
            Wrap(
              spacing: 8,
              children: [
                if (v.lastCheckOk == false)
                  FilledButton(
                    onPressed: widget.onRetry,
                    child: Text(l.commonRetry),
                  ),
                OutlinedButton(
                  onPressed: widget.onDisconnect,
                  child: Text(l.intDisconnect),
                ),
              ],
            ),
        ] else if (_pasting && widget.canManage) ...[
          Text('1. ${l.intCfStep1}'),
          Text('2. ${l.intCfStep2}'),
          Text('3. ${l.intCfStep3}'),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const <String>[],
            decoration: InputDecoration(
              labelText: l.intCfField,
              // INT-23: icon and text below the field.
              error: _error == null
                  ? null
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 16,
                          color: context.ps.danger,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(color: context.ps.danger),
                          ),
                        ),
                      ],
                    ),
            ),
            // One paste: a whole token arrives at once, then podship checks
            // and saves it without another click.
            onChanged: (t) {
              final v = t.trim();
              if (!_busy && v.length >= 30 && !v.contains(' ')) _save();
            },
            onSubmitted: (_) => _save(),
          ),
          if (_busy) ...[
            const SizedBox(height: 8),
            Text(l.intCfChecking, style: TextStyle(color: context.ps.ink2)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(l.intCfSave),
              ),
              TextButton(onPressed: _open, child: Text(l.intCfReopen)),
            ],
          ),
        ] else ...[
          perms,
          if (widget.canManage)
            Semantics(
              button: true,
              label: '${l.intConnect} Cloudflare ${l.commonNewTab}',
              excludeSemantics: true,
              child: FilledButton.icon(
                onPressed: _open,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(l.intConnect),
              ),
            ),
        ],
      ],
    );
  }
}

// --- AWS ------------------------------------------------------------------------

class _AwsCard extends StatelessWidget {
  const _AwsCard({
    required this.view,
    required this.canManage,
    required this.onConnect,
    required this.onDisconnect,
    required this.onRetry,
  });
  final IntegrationView? view;
  final bool canManage;
  final Future<void> Function() onConnect;
  final VoidCallback onDisconnect;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final v = view;
    final status = v?.status ?? 'off';
    final perms = _Permissions([l.intAwsPerm1, l.intAwsPerm2]);
    return _Card(
      title: 'AWS',
      icon: Icons.mail_outline,
      status: status,
      children: [
        Text(l.intAwsWhat),
        const SizedBox(height: 12),
        if (status == 'connected') ...[
          _checkFailed(context, 'AWS', v!),
          _Facts([
            (l.intAwsAccount, Text(v.account ?? '', style: mono(context))),
            (l.intAwsRole, Text(v.role ?? '', style: mono(context))),
            (
              l.intAwsSes,
              Text(
                l.intAwsSesMode(
                  v.sesRegion ?? '',
                  v.sesProduction == true
                      ? l.intAwsSesProd
                      : l.intAwsSesSandbox,
                ),
              ),
            ),
            (
              l.intConnectedLabel,
              Text(
                l.intConnectedBy(
                  v.connectedBy ?? '',
                  _date(context, v.connectedAt),
                ),
              ),
            ),
          ]),
          Text(
            l.intAwsNoKeys,
            style: TextStyle(fontSize: 12, color: context.ps.ink2),
          ),
          perms,
          if (canManage)
            Wrap(
              spacing: 8,
              children: [
                if (v.lastCheckOk == false)
                  FilledButton(onPressed: onRetry, child: Text(l.commonRetry)),
                OutlinedButton(
                  onPressed: onDisconnect,
                  child: Text(l.intDisconnect),
                ),
              ],
            ),
        ] else if (status == 'pending' && canManage) ...[
          Text('1. ${l.intAwsStep1}'),
          Text('2. ${l.intAwsStep2}'),
          Text('3. ${l.intAwsStep3}'),
          const SizedBox(height: 8),
          if (v?.lastError != null)
            _Banner(
              icon: Icons.warning_amber,
              text: l.intAwsFailed(v!.lastError!),
              color: context.ps.warnC,
            )
          else
            Text(
              l.intAwsWaiting(_time(context, v?.pendingSince)),
              style: TextStyle(color: context.ps.ink2),
            ),
          const SizedBox(height: 12),
          if (v?.ready == false)
            Text(l.intAwsNotReady, style: TextStyle(color: context.ps.ink2))
          else
            OutlinedButton(onPressed: onConnect, child: Text(l.intAwsAgain)),
        ] else ...[
          perms,
          if (canManage && v?.ready == false)
            Text(
              l.intAwsNotReady,
              style: TextStyle(color: context.ps.ink2),
            )
          else if (canManage)
            Semantics(
              button: true,
              label: '${l.intConnect} AWS ${l.commonNewTab}',
              excludeSemantics: true,
              child: FilledButton.icon(
                onPressed: onConnect,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(l.intConnect),
              ),
            ),
        ],
      ],
    );
  }
}
