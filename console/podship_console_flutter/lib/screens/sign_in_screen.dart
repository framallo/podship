import 'package:flutter/material.dart';
import 'package:podship_console_client/podship_console_client.dart';

import 'package:serverpod_auth_idp_flutter/serverpod_auth_idp_flutter.dart';

import '../client.dart';
import '../l10n/gen/app_localizations.dart';
import '../theme.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.linkToken});
  final String? linkToken;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    if (widget.linkToken != null) _redeem(widget.linkToken!);
  }

  Future<void> _redeem(String token) async {
    setState(() => _busy = true);
    try {
      final s = await client.emailCode.redeemLink(token);
      await client.auth.updateSignedInUser(s);
    } on EmailCodeException {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).signInLinkUsed);
      }
    } on Object {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).commonError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _msg(AppLocalizations l, EmailCodeFailure f) => switch (f) {
    EmailCodeFailure.invalidEmail => l.signInBadEmail,
    EmailCodeFailure.deliveryFailed => l.signInNoMail,
    EmailCodeFailure.tooManyAttempts => l.signInTooMany,
    EmailCodeFailure.invalidCode ||
    EmailCodeFailure.expired ||
    EmailCodeFailure.notFound => l.signInBadCode,
    EmailCodeFailure.noAccess => l.commonForbidden,
  };

  Future<void> _send() async {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await client.emailCode.requestCode(_email.text, locale);
      setState(() {
        _codeSent = true;
        _info = l.signInCodeSent(_email.text.trim());
      });
    } on EmailCodeException catch (e) {
      setState(() => _error = _msg(l, e.reason));
    } on Object {
      setState(() => _error = l.commonError);
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await client.emailCode.verifyCode(_email.text, _code.text);
      await client.auth.updateSignedInUser(s);
    } on EmailCodeException catch (e) {
      setState(() => _error = _msg(l, e.reason));
    } on Object {
      setState(() => _error = l.commonError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final linking = widget.linkToken != null && _busy;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Brand(),
                      const SizedBox(height: 24),
                      Semantics(
                        header: true,
                        child: Text(
                          l.signInTitle,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (linking)
                        Text(l.signInLinkWorking)
                      else ...[
                        TextField(
                          controller: _email,
                          enabled: !_codeSent,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: InputDecoration(labelText: l.signInEmail),
                          onSubmitted: (_) => _send(),
                        ),
                        if (_codeSent) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _code,
                            keyboardType: TextInputType.number,
                            autofillHints: const [AutofillHints.oneTimeCode],
                            decoration: InputDecoration(
                              labelText: l.signInCode,
                            ),
                            onSubmitted: (_) => _verify(),
                          ),
                        ],
                        if (_info != null && _error == null) ...[
                          const SizedBox(height: 12),
                          Text(_info!),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          _ErrorText(_error!),
                        ],
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : (_codeSent ? _verify : _send),
                          child: Text(
                            _codeSent ? l.signInVerify : l.signInSendCode,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => Row(
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
      Text(
        'podship',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: 16, color: context.ps.danger),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(color: context.ps.danger)),
        ),
      ],
    ),
  );
}
