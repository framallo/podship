import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'podship console'**
  String get appTitle;

  /// No description provided for @signInTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to podship console'**
  String get signInTitle;

  /// No description provided for @signInEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get signInEmail;

  /// No description provided for @signInSendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get signInSendCode;

  /// No description provided for @signInCode.
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get signInCode;

  /// No description provided for @signInVerify.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signInVerify;

  /// No description provided for @signInCodeSent.
  ///
  /// In en, this message translates to:
  /// **'If {email} can use this console, a code is on its way.'**
  String signInCodeSent(Object email);

  /// No description provided for @signInNoMail.
  ///
  /// In en, this message translates to:
  /// **'This console can\'t send email yet. Ask the owner for a sign-in link.'**
  String get signInNoMail;

  /// No description provided for @signInBadCode.
  ///
  /// In en, this message translates to:
  /// **'This code is wrong or expired. Ask for a new one.'**
  String get signInBadCode;

  /// No description provided for @signInBadEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter an email like name@example.com.'**
  String get signInBadEmail;

  /// No description provided for @signInTooMany.
  ///
  /// In en, this message translates to:
  /// **'Too many tries. Wait a few minutes.'**
  String get signInTooMany;

  /// No description provided for @signInLinkUsed.
  ///
  /// In en, this message translates to:
  /// **'This sign-in link was used or expired. Ask for a new one.'**
  String get signInLinkUsed;

  /// No description provided for @signInLinkWorking.
  ///
  /// In en, this message translates to:
  /// **'Signing you in…'**
  String get signInLinkWorking;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @settingsIntegrations.
  ///
  /// In en, this message translates to:
  /// **'Integrations'**
  String get settingsIntegrations;

  /// No description provided for @intTitle.
  ///
  /// In en, this message translates to:
  /// **'Integrations'**
  String get intTitle;

  /// No description provided for @intLead.
  ///
  /// In en, this message translates to:
  /// **'Connect each provider once. Every project in {workspace} uses the connection.'**
  String intLead(Object workspace);

  /// No description provided for @intStatusOff.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get intStatusOff;

  /// No description provided for @intStatusOn.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get intStatusOn;

  /// No description provided for @intStatusWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for AWS'**
  String get intStatusWaiting;

  /// No description provided for @intConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get intConnect;

  /// No description provided for @intDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect…'**
  String get intDisconnect;

  /// No description provided for @intCfWhat.
  ///
  /// In en, this message translates to:
  /// **'DNS records, tunnel routes and Access for your domains.'**
  String get intCfWhat;

  /// No description provided for @intCfStep1.
  ///
  /// In en, this message translates to:
  /// **'In the Cloudflare tab: Continue to summary.'**
  String get intCfStep1;

  /// No description provided for @intCfStep2.
  ///
  /// In en, this message translates to:
  /// **'Create Token.'**
  String get intCfStep2;

  /// No description provided for @intCfStep3.
  ///
  /// In en, this message translates to:
  /// **'Copy. Then paste the token here: podship checks and saves it at once.'**
  String get intCfStep3;

  /// No description provided for @intCfField.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare API token'**
  String get intCfField;

  /// No description provided for @intCfSave.
  ///
  /// In en, this message translates to:
  /// **'Save and check'**
  String get intCfSave;

  /// No description provided for @intCfReopen.
  ///
  /// In en, this message translates to:
  /// **'Open Cloudflare again'**
  String get intCfReopen;

  /// No description provided for @intCfEmpty.
  ///
  /// In en, this message translates to:
  /// **'Paste the token you copied in Cloudflare.'**
  String get intCfEmpty;

  /// No description provided for @intCfInactive.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare says this token is not active. Create a new one.'**
  String get intCfInactive;

  /// No description provided for @intCfMissing.
  ///
  /// In en, this message translates to:
  /// **'This token can\'t {permission}. Create it again from the link, without changing the permissions.'**
  String intCfMissing(Object permission);

  /// No description provided for @intCfInvalid.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare doesn\'t know this token. Check that you pasted all of it.'**
  String get intCfInvalid;

  /// No description provided for @intCfAccount.
  ///
  /// In en, this message translates to:
  /// **'Account {name} · {zones} zones'**
  String intCfAccount(Object name, Object zones);

  /// No description provided for @intPermissions.
  ///
  /// In en, this message translates to:
  /// **'What podship can do'**
  String get intPermissions;

  /// No description provided for @intCfPerm1.
  ///
  /// In en, this message translates to:
  /// **'Zone: Read · DNS: Edit · SSL and Certificates: Read'**
  String get intCfPerm1;

  /// No description provided for @intCfPerm2.
  ///
  /// In en, this message translates to:
  /// **'Account: Cloudflare Tunnel: Edit · Access: Apps and Policies: Edit'**
  String get intCfPerm2;

  /// No description provided for @intCfRevokeHint.
  ///
  /// In en, this message translates to:
  /// **'Delete the token \"podship console\" in Cloudflare too. podship can\'t delete it for you.'**
  String get intCfRevokeHint;

  /// No description provided for @intCfRevokeLink.
  ///
  /// In en, this message translates to:
  /// **'Cloudflare API tokens'**
  String get intCfRevokeLink;

  /// No description provided for @intAwsWhat.
  ///
  /// In en, this message translates to:
  /// **'Email sending with Amazon SES: domains, DKIM and a sending user per app.'**
  String get intAwsWhat;

  /// No description provided for @intAwsStep1.
  ///
  /// In en, this message translates to:
  /// **'In the AWS tab: sign in if AWS asks.'**
  String get intAwsStep1;

  /// No description provided for @intAwsStep2.
  ///
  /// In en, this message translates to:
  /// **'At the bottom, tick the box that acknowledges IAM resources.'**
  String get intAwsStep2;

  /// No description provided for @intAwsStep3.
  ///
  /// In en, this message translates to:
  /// **'Click \"Create stack\". This card turns to Connected by itself.'**
  String get intAwsStep3;

  /// No description provided for @intAwsWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the stack since {time}. This page updates by itself.'**
  String intAwsWaiting(Object time);

  /// No description provided for @intAwsAgain.
  ///
  /// In en, this message translates to:
  /// **'Open AWS again'**
  String get intAwsAgain;

  /// No description provided for @intAwsAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get intAwsAccount;

  /// No description provided for @intAwsRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get intAwsRole;

  /// No description provided for @intAwsSes.
  ///
  /// In en, this message translates to:
  /// **'SES'**
  String get intAwsSes;

  /// No description provided for @intAwsSesMode.
  ///
  /// In en, this message translates to:
  /// **'{region}: {mode}'**
  String intAwsSesMode(Object mode, Object region);

  /// No description provided for @intAwsSesProd.
  ///
  /// In en, this message translates to:
  /// **'production access'**
  String get intAwsSesProd;

  /// No description provided for @intAwsSesSandbox.
  ///
  /// In en, this message translates to:
  /// **'sandbox'**
  String get intAwsSesSandbox;

  /// No description provided for @intAwsNoKeys.
  ///
  /// In en, this message translates to:
  /// **'podship uses a role. No access keys exist.'**
  String get intAwsNoKeys;

  /// No description provided for @intAwsPerm1.
  ///
  /// In en, this message translates to:
  /// **'SES: identities, DKIM, MAIL FROM, send a test'**
  String get intAwsPerm1;

  /// No description provided for @intAwsPerm2.
  ///
  /// In en, this message translates to:
  /// **'IAM: users under /podship-ses/ that can only send email'**
  String get intAwsPerm2;

  /// No description provided for @intAwsRevokeHint.
  ///
  /// In en, this message translates to:
  /// **'Delete the stack \"podship\" in CloudFormation to remove the role.'**
  String get intAwsRevokeHint;

  /// No description provided for @intAwsRevokeLink.
  ///
  /// In en, this message translates to:
  /// **'CloudFormation stacks'**
  String get intAwsRevokeLink;

  /// No description provided for @intToken.
  ///
  /// In en, this message translates to:
  /// **'Token'**
  String get intToken;

  /// No description provided for @intTokenEnds.
  ///
  /// In en, this message translates to:
  /// **'ends in {hint}'**
  String intTokenEnds(Object hint);

  /// No description provided for @intConnectedLabel.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get intConnectedLabel;

  /// No description provided for @intConnectedBy.
  ///
  /// In en, this message translates to:
  /// **'by {person} on {date}'**
  String intConnectedBy(Object date, Object person);

  /// No description provided for @intLastCheck.
  ///
  /// In en, this message translates to:
  /// **'Last check'**
  String get intLastCheck;

  /// No description provided for @intCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'podship couldn\'t reach {provider} at {time}. The connection is still saved.'**
  String intCheckFailed(Object provider, Object time);

  /// No description provided for @intOnlyAdmins.
  ///
  /// In en, this message translates to:
  /// **'Only workspace owners and admins can connect or disconnect providers.'**
  String get intOnlyAdmins;

  /// No description provided for @intDisconnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Disconnect {provider}?'**
  String intDisconnectTitle(Object provider);

  /// No description provided for @intDisconnectCf.
  ///
  /// In en, this message translates to:
  /// **'podship stops changing DNS, tunnels and Access for every project in {workspace}. Your sites keep working.'**
  String intDisconnectCf(Object workspace);

  /// No description provided for @intDisconnectAws.
  ///
  /// In en, this message translates to:
  /// **'podship stops setting up email for every project in {workspace}. Apps keep sending with their own sending users.'**
  String intDisconnectAws(Object workspace);

  /// No description provided for @intDisconnectConfirm.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get intDisconnectConfirm;

  /// No description provided for @intDisconnected.
  ///
  /// In en, this message translates to:
  /// **'{provider} is disconnected.'**
  String intDisconnected(Object provider);

  /// No description provided for @intConnectedNow.
  ///
  /// In en, this message translates to:
  /// **'{provider} is connected.'**
  String intConnectedNow(Object provider);

  /// No description provided for @intAwsFailed.
  ///
  /// In en, this message translates to:
  /// **'AWS answered, but podship couldn\'t use the role: {error}. Download the template again and update the stack.'**
  String intAwsFailed(Object error);

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonNewTab.
  ///
  /// In en, this message translates to:
  /// **'(opens in a new tab)'**
  String get commonNewTab;

  /// No description provided for @commonError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get commonError;

  /// No description provided for @commonForbidden.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have access to this.'**
  String get commonForbidden;

  /// No description provided for @intAwsNotReady.
  ///
  /// In en, this message translates to:
  /// **'AWS can\'t connect yet: the podship template is not published. Ask the podship owner.'**
  String get intAwsNotReady;

  /// No description provided for @intCfChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking the token…'**
  String get intCfChecking;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
