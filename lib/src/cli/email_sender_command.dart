// `podship email sender`: the app's own SES sending user (`<project>-ses`),
// made through the workspace's AWS integration in the podship console. The
// user may only send from the environment's SES identity; its key becomes the
// app's secrets. podship-design: decisions/2026-10-09-integrations-phase-1.

import '../integrations/iam.dart';
import '../integrations/secrets.dart';
import '../ops/app_ops.dart';
import '../ops/context.dart';
import 'base.dart';

class EmailSenderCommand extends PodshipCommand {
  EmailSenderCommand() {
    argParser
      ..addOption(
        'user',
        help:
            'The IAM user name (default: <project>-ses), under /podship-ses/.',
      )
      ..addOption(
        'key-id-env',
        defaultsTo: 'AWS_ACCESS_KEY_ID',
        help: 'The app secret that gets the access key id.',
      )
      ..addOption(
        'secret-env',
        defaultsTo: 'AWS_SECRET_ACCESS_KEY',
        help: 'The app secret that gets the secret access key.',
      )
      ..addFlag(
        'rotate',
        help:
            'Make a new key and delete the older ones (after the new one exists).',
      );
  }

  @override
  String get name => 'sender';
  @override
  String get description =>
      'Make the app\'s own SES sending user (send-only, from its identity) and store its key as the app\'s secrets.';
  @override
  bool get mutating => true;

  @override
  Future<int> execute() async {
    final e = env;
    final email = e.email;
    if (email == null) throw Aborted('${e.name} has no email: section');
    final identity =
        email.identity ?? email.from.replaceAll(RegExp(r'.*@|>.*'), '');
    final user = (argResults!['user'] as String?) ?? '${config.project}-ses';
    final keyIdEnv = argResults!['key-id-env'] as String;
    final secretEnv = argResults!['secret-env'] as String;
    final rotate = argResults!['rotate'] as bool;
    final creds = Integrations().secrets.read(awsCredentialsKey);
    if (creds == null) {
      throw Aborted(
        'no AWS credentials: connect AWS in the podship console '
        '(Settings > Integrations), then `podship login <console-url>`',
      );
    }
    log.info(
      'IAM user /podship-ses/$user: send from $identity in ${email.region} only; '
      'key into $keyIdEnv and $secretEnv of ${config.project}/${e.name}',
    );
    if (dryRun) return 0;
    if (!ctx.confirm(
      '${rotate ? 'Rotate' : 'Create'} the sending key of $user and store it in ${e.name}?',
    )) {
      throw Aborted('cancelled');
    }
    final iam = IamApi(AwsCredentials.fromJson(creds));
    final r = await iam.ensureSender(
      name: user,
      region: email.region,
      identity: identity,
      project: '${config.project}/${e.name}',
      rotate: rotate,
    );
    log.ok(
      '${r.created ? 'created' : 'kept'} $user; new key …'
      '${r.key.accessKeyId.substring(r.key.accessKeyId.length - 4)}'
      '${r.deleted.isEmpty ? '' : '; deleted ${r.deleted.length} older key(s)'}',
    );
    var code = await runOp(api.secretSet(e.name, keyIdEnv, r.key.accessKeyId));
    if (code != 0) return code;
    code = await runOp(api.secretSet(e.name, secretEnv, r.key.secretAccessKey));
    if (code == 0) {
      log.info(
        'restart or deploy ${e.name} so the app reads the new key '
        '(`podship restart --env ${e.name}`)',
      );
    }
    return code;
  }
}
