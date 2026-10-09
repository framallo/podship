// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'podship console';

  @override
  String get signInTitle => 'Sign in to podship console';

  @override
  String get signInEmail => 'Email';

  @override
  String get signInSendCode => 'Send code';

  @override
  String get signInCode => '6-digit code';

  @override
  String get signInVerify => 'Sign in';

  @override
  String signInCodeSent(Object email) {
    return 'If $email can use this console, a code is on its way.';
  }

  @override
  String get signInNoMail =>
      'This console can\'t send email yet. Ask the owner for a sign-in link.';

  @override
  String get signInBadCode =>
      'This code is wrong or expired. Ask for a new one.';

  @override
  String get signInBadEmail => 'Enter an email like name@example.com.';

  @override
  String get signInTooMany => 'Too many tries. Wait a few minutes.';

  @override
  String get signInLinkUsed =>
      'This sign-in link was used or expired. Ask for a new one.';

  @override
  String get signInLinkWorking => 'Signing you in…';

  @override
  String get signOut => 'Sign out';

  @override
  String get navSettings => 'Settings';

  @override
  String get settingsIntegrations => 'Integrations';

  @override
  String get intTitle => 'Integrations';

  @override
  String intLead(Object workspace) {
    return 'Connect each provider once. Every project in $workspace uses the connection.';
  }

  @override
  String get intStatusOff => 'Not connected';

  @override
  String get intStatusOn => 'Connected';

  @override
  String get intStatusWaiting => 'Waiting for AWS';

  @override
  String get intConnect => 'Connect';

  @override
  String get intDisconnect => 'Disconnect…';

  @override
  String get intCfWhat =>
      'DNS records, tunnel routes and Access for your domains.';

  @override
  String get intCfStep1 => 'In the Cloudflare tab: Continue to summary.';

  @override
  String get intCfStep2 => 'Create Token.';

  @override
  String get intCfStep3 => 'Copy. Then paste the token here.';

  @override
  String get intCfField => 'Cloudflare API token';

  @override
  String get intCfSave => 'Save and check';

  @override
  String get intCfReopen => 'Open Cloudflare again';

  @override
  String get intCfEmpty => 'Paste the token you copied in Cloudflare.';

  @override
  String get intCfInactive =>
      'Cloudflare says this token is not active. Create a new one.';

  @override
  String intCfMissing(Object permission) {
    return 'This token can\'t $permission. Create it again from the link, without changing the permissions.';
  }

  @override
  String get intCfInvalid =>
      'Cloudflare doesn\'t know this token. Check that you pasted all of it.';

  @override
  String intCfAccount(Object name, Object zones) {
    return 'Account $name · $zones zones';
  }

  @override
  String get intPermissions => 'What podship can do';

  @override
  String get intCfPerm1 =>
      'Zone: Read · DNS: Edit · SSL and Certificates: Read';

  @override
  String get intCfPerm2 =>
      'Account: Cloudflare Tunnel: Edit · Access: Apps and Policies: Edit';

  @override
  String get intCfRevokeHint =>
      'Delete the token \"podship console\" in Cloudflare too. podship can\'t delete it for you.';

  @override
  String get intCfRevokeLink => 'Cloudflare API tokens';

  @override
  String get intAwsWhat =>
      'Email sending with Amazon SES: domains, DKIM and a sending user per app.';

  @override
  String intAwsDownloaded(Object file) {
    return 'Your browser downloaded $file.';
  }

  @override
  String get intAwsStep1 => 'In the AWS tab: sign in.';

  @override
  String get intAwsStep2 =>
      'Choose \"Upload a template file\" and pick the file.';

  @override
  String get intAwsStep3 => 'Next. Stack name: podship. Next, Next.';

  @override
  String get intAwsStep4 =>
      'Check the box that acknowledges IAM resources. Submit.';

  @override
  String intAwsWaiting(Object time) {
    return 'Waiting for the stack since $time. This page updates by itself.';
  }

  @override
  String get intAwsAgain => 'Download the template again';

  @override
  String get intAwsAccount => 'Account';

  @override
  String get intAwsRole => 'Role';

  @override
  String get intAwsSes => 'SES';

  @override
  String intAwsSesMode(Object mode, Object region) {
    return '$region: $mode';
  }

  @override
  String get intAwsSesProd => 'production access';

  @override
  String get intAwsSesSandbox => 'sandbox';

  @override
  String get intAwsNoKeys => 'podship uses a role. No access keys exist.';

  @override
  String get intAwsPerm1 => 'SES: identities, DKIM, MAIL FROM, send a test';

  @override
  String get intAwsPerm2 =>
      'IAM: users under /podship-ses/ that can only send email';

  @override
  String get intAwsRevokeHint =>
      'Delete the stack \"podship\" in CloudFormation to remove the role.';

  @override
  String get intAwsRevokeLink => 'CloudFormation stacks';

  @override
  String get intToken => 'Token';

  @override
  String intTokenEnds(Object hint) {
    return 'ends in $hint';
  }

  @override
  String get intConnectedLabel => 'Connected';

  @override
  String intConnectedBy(Object date, Object person) {
    return 'by $person on $date';
  }

  @override
  String get intLastCheck => 'Last check';

  @override
  String intCheckFailed(Object provider, Object time) {
    return 'podship couldn\'t reach $provider at $time. The connection is still saved.';
  }

  @override
  String get intOnlyAdmins =>
      'Only workspace owners and admins can connect or disconnect providers.';

  @override
  String intDisconnectTitle(Object provider) {
    return 'Disconnect $provider?';
  }

  @override
  String intDisconnectCf(Object workspace) {
    return 'podship stops changing DNS, tunnels and Access for every project in $workspace. Your sites keep working.';
  }

  @override
  String intDisconnectAws(Object workspace) {
    return 'podship stops setting up email for every project in $workspace. Apps keep sending with their own sending users.';
  }

  @override
  String get intDisconnectConfirm => 'Disconnect';

  @override
  String intDisconnected(Object provider) {
    return '$provider is disconnected.';
  }

  @override
  String intConnectedNow(Object provider) {
    return '$provider is connected.';
  }

  @override
  String intAwsFailed(Object error) {
    return 'AWS answered, but podship couldn\'t use the role: $error. Download the template again and update the stack.';
  }

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonNewTab => '(opens in a new tab)';

  @override
  String get commonError => 'Something went wrong. Try again.';

  @override
  String get commonForbidden => 'You don\'t have access to this.';
}
