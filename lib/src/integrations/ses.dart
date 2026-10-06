// Amazon SES (API v2, REST/JSON, signed with SigV4).
//
// The IAM user (or role) needs, on the identities it manages:
//   ses:GetAccount, ses:GetEmailIdentity, ses:CreateEmailIdentity,
//   ses:DeleteEmailIdentity, ses:PutEmailIdentityMailFromAttributes,
//   ses:TagResource, ses:SendEmail
// (see the README, "Cloudflare and SES", for a policy).

import 'dart:convert';

import 'http.dart';
import 'secrets.dart';
import 'sigv4.dart';

class SesException implements Exception {
  SesException(this.status, this.type, this.message);
  final int status;

  /// Like `NotFoundException`.
  final String type;
  final String message;
  @override
  String toString() => 'SES: $type: $message (HTTP $status)';
}

/// The SES account in a region.
class SesAccount {
  SesAccount({
    required this.production,
    required this.sendingEnabled,
    required this.max24h,
    required this.maxRate,
    required this.sent24h,
    this.enforcement,
  });
  factory SesAccount.fromJson(Map j) {
    final q = (j['SendQuota'] as Map?) ?? const {};
    return SesAccount(
      production: j['ProductionAccessEnabled'] == true,
      sendingEnabled: j['SendingEnabled'] != false,
      max24h: (q['Max24HourSend'] as num? ?? 0).toDouble(),
      maxRate: (q['MaxSendRate'] as num? ?? 0).toDouble(),
      sent24h: (q['SentLast24Hours'] as num? ?? 0).toDouble(),
      enforcement: j['EnforcementStatus'] as String?,
    );
  }

  /// Out of the sandbox: may send to any address.
  final bool production;
  final bool sendingEnabled;
  final double max24h;
  final double maxRate;
  final double sent24h;

  /// `HEALTHY`, `PROBATION` or `SHUTDOWN`.
  final String? enforcement;

  Map<String, Object?> toJson() => {
    'production': production,
    'sandbox': !production,
    'sending_enabled': sendingEnabled,
    'quota': {
      'max_24h': max24h,
      'max_per_second': maxRate,
      'sent_24h': sent24h,
    },
    'enforcement': ?enforcement,
  };
}

/// An email identity (a domain or an address).
class SesIdentity {
  SesIdentity({
    required this.name,
    required this.type,
    required this.verifiedForSending,
    this.verificationStatus,
    this.dkimStatus,
    this.dkimTokens = const [],
    this.dkimSigning = false,
    this.mailFromDomain,
    this.mailFromStatus,
    this.tags = const {},
  });
  factory SesIdentity.fromJson(String name, Map j) {
    final dkim = (j['DkimAttributes'] as Map?) ?? const {};
    final mf = (j['MailFromAttributes'] as Map?) ?? const {};
    return SesIdentity(
      name: name,
      type: '${j['IdentityType'] ?? 'DOMAIN'}',
      verifiedForSending: j['VerifiedForSendingStatus'] == true,
      verificationStatus: j['VerificationStatus'] as String?,
      dkimStatus: dkim['Status'] as String?,
      dkimTokens: [for (final t in (dkim['Tokens'] as List? ?? const [])) '$t'],
      dkimSigning: dkim['SigningEnabled'] == true,
      mailFromDomain: mf['MailFromDomain'] as String?,
      mailFromStatus: mf['MailFromDomainStatus'] as String?,
      tags: {
        for (final t in (j['Tags'] as List? ?? const []).cast<Map>())
          '${t['Key']}': '${t['Value']}',
      },
    );
  }

  final String name;

  /// `DOMAIN` or `EMAIL_ADDRESS`.
  final String type;
  final bool verifiedForSending;

  /// `PENDING`, `SUCCESS`, `FAILED`, `TEMPORARY_FAILURE`, `NOT_STARTED`.
  final String? verificationStatus;
  final String? dkimStatus;
  final List<String> dkimTokens;
  final bool dkimSigning;
  final String? mailFromDomain;
  final String? mailFromStatus;
  final Map<String, String> tags;

  Map<String, Object?> toJson() => {
    'name': name,
    'type': type,
    'verified_for_sending': verifiedForSending,
    'verification_status': ?verificationStatus,
    'dkim_status': ?dkimStatus,
    'dkim_signing': dkimSigning,
    'dkim_records': [for (final r in dkimRecords(name, dkimTokens)) r.$3],
    'mail_from_domain': ?mailFromDomain,
    'mail_from_status': ?mailFromStatus,
    if (tags.isNotEmpty) 'tags': tags,
  };
}

/// The Easy DKIM CNAMEs of [domain]: (name, target, description).
List<(String, String, String)> dkimRecords(
  String domain,
  List<String> tokens,
) => [
  for (final t in tokens)
    (
      '$t._domainkey.$domain',
      '$t.dkim.amazonses.com',
      'CNAME $t._domainkey.$domain → $t.dkim.amazonses.com',
    ),
];

/// The MX and SPF records of a custom MAIL FROM domain in [region].
({String mx, String spf}) mailFromRecords(String region) => (
  mx: 'feedback-smtp.$region.amazonses.com',
  spf: '"v=spf1 include:amazonses.com ~all"',
);

class SesApi {
  SesApi(
    this._creds, {
    required this.region,
    HttpTransport? transport,
    String? endpoint,
    DateTime Function()? clock,
  }) : transport = transport ?? IoTransport(),
       endpoint = endpoint ?? 'https://email.$region.amazonaws.com',
       _clock = clock ?? DateTime.now;
  final AwsCredentials _creds;
  final String region;
  final HttpTransport transport;
  final String endpoint;
  final DateTime Function() _clock;

  /// A client that can only read (for plans).
  SesApi readOnly() => SesApi(
    _creds,
    region: region,
    transport: ReadOnlyTransport(transport),
    endpoint: endpoint,
    clock: _clock,
  );

  Future<Map> _call(String method, String path, [Object? body]) async {
    final call = HttpCall(
      method,
      Uri.parse('$endpoint$path'),
      headers: {
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
      },
      body: body == null ? null : jsonEncode(body),
    );
    final signed = signV4(
      call,
      _creds,
      region: region,
      service: 'ses',
      now: _clock(),
    ).call;
    final reply = await transport.send(signed);
    Map j = const {};
    try {
      j = (reply.json as Map?) ?? const {};
    } catch (_) {}
    if (reply.status >= 400) {
      final type = (reply.headers['x-amzn-errortype'] ?? '${j['__type'] ?? ''}')
          .split(':')
          .first;
      throw SesException(
        reply.status,
        type.isEmpty
            ? (reply.status == 404 ? 'NotFoundException' : 'Error')
            : type,
        '${j['message'] ?? j['Message'] ?? '$method $path failed'}',
      );
    }
    return j;
  }

  static String _id(String identity) => awsEncode(identity);

  Future<SesAccount> account() async =>
      SesAccount.fromJson(await _call('GET', '/v2/email/account'));

  /// The identity, or null when SES does not know it.
  Future<SesIdentity?> identity(String name) async {
    try {
      return SesIdentity.fromJson(
        name,
        await _call('GET', '/v2/email/identities/${_id(name)}'),
      );
    } on SesException catch (e) {
      if (e.status == 404 || e.type == 'NotFoundException') return null;
      rethrow;
    }
  }

  /// Creates a domain identity with Easy DKIM. Returns it (with the DKIM
  /// tokens whose CNAMEs must be published).
  Future<SesIdentity> createIdentity(
    String domain, {
    Map<String, String> tags = const {},
  }) async {
    final j = await _call('POST', '/v2/email/identities', {
      'EmailIdentity': domain,
      if (tags.isNotEmpty)
        'Tags': [
          for (final t in tags.entries) {'Key': t.key, 'Value': t.value},
        ],
    });
    return SesIdentity.fromJson(domain, {...j, 'Tags': ?_tagList(tags)});
  }

  static List<Map>? _tagList(Map<String, String> tags) => tags.isEmpty
      ? null
      : [
          for (final t in tags.entries) {'Key': t.key, 'Value': t.value},
        ];

  Future<void> deleteIdentity(String name) =>
      _call('DELETE', '/v2/email/identities/${_id(name)}');

  /// Sets (or with null, removes) the custom MAIL FROM domain.
  Future<void> putMailFrom(String identity, String? mailFromDomain) =>
      _call('PUT', '/v2/email/identities/${_id(identity)}/mail-from', {
        'MailFromDomain': ?mailFromDomain,
        if (mailFromDomain != null) 'BehaviorOnMxFailure': 'USE_DEFAULT_VALUE',
      });

  /// Sends a plain-text email. Returns the message id.
  Future<String> send({
    required String from,
    required List<String> to,
    required String subject,
    required String text,
  }) async {
    final j = await _call('POST', '/v2/email/outbound-emails', {
      'FromEmailAddress': from,
      'Destination': {'ToAddresses': to},
      'Content': {
        'Simple': {
          'Subject': {'Data': subject, 'Charset': 'UTF-8'},
          'Body': {
            'Text': {'Data': text, 'Charset': 'UTF-8'},
          },
        },
      },
    });
    return '${j['MessageId']}';
  }
}

/// Whether an address can send, and why.
class SendCheck {
  SendCheck({
    required this.address,
    required this.domain,
    required this.region,
    required this.account,
    required this.identities,
    this.sendingIdentity,
  });
  final String address;
  final String domain;
  final String region;
  final SesAccount account;

  /// The identities that were looked up (the address, the domain, its
  /// parents), with null for the ones SES does not know.
  final Map<String, SesIdentity?> identities;

  /// The verified identity that lets [address] send, if any.
  final String? sendingIdentity;

  bool get canSend => sendingIdentity != null && account.sendingEnabled;

  /// The identity of the domain itself, if SES has it.
  SesIdentity? get domainIdentity => identities[domain];

  List<String> get problems => [
    if (sendingIdentity == null)
      'no verified identity for $address (checked ${identities.keys.join(', ')})',
    if (!account.sendingEnabled)
      'sending is paused for this account in $region',
    if (!account.production)
      'the account is in the SES sandbox in $region: it can only send to verified addresses '
          '(ask AWS for production access)',
    if (account.enforcement != null && account.enforcement != 'HEALTHY')
      'account enforcement status: ${account.enforcement}',
  ];

  Map<String, Object?> toJson() => {
    'address': address,
    'domain': domain,
    'region': region,
    'can_send': canSend,
    'sending_identity': ?sendingIdentity,
    'account': account.toJson(),
    'identities': {
      for (final e in identities.entries) e.key: e.value?.toJson(),
    },
    'problems': problems,
  };
}

/// The address in `Name <hola@app.example>` or `hola@app.example`.
String emailAddress(String from) {
  final m = RegExp(r'<([^>]+)>').firstMatch(from);
  return (m?.group(1) ?? from).trim();
}

/// Looks up whether [from] can send: the address itself, then its domain,
/// then each parent domain (a verified domain lets its subdomains send).
Future<SendCheck> checkSender(SesApi ses, String from) async {
  final address = emailAddress(from);
  final at = address.lastIndexOf('@');
  if (at < 1) {
    throw SesException(400, 'InvalidAddress', 'not an address: $from');
  }
  final domain = address.substring(at + 1).toLowerCase();
  final labels = domain.split('.');
  final names = [
    address,
    for (var i = 0; i < labels.length - 1; i++) labels.sublist(i).join('.'),
  ];
  final account = await ses.account();
  final found = <String, SesIdentity?>{};
  String? sending;
  for (final n in names) {
    final id = await ses.identity(n);
    found[n] = id;
    if (id != null && id.verifiedForSending) {
      sending = n;
      break;
    }
  }
  return SendCheck(
    address: address,
    domain: domain,
    region: ses.region,
    account: account,
    identities: found,
    sendingIdentity: sending,
  );
}
