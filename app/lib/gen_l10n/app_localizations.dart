import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_nl.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen_l10n/app_localizations.dart';
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

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
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
    Locale('nl'),
  ];

  /// The application title
  ///
  /// In en, this message translates to:
  /// **'Zegel'**
  String get appTitle;

  /// Title shown on the home screen
  ///
  /// In en, this message translates to:
  /// **'Zegel - Tamper-Proof Sealing'**
  String get homeTitle;

  /// Label for the seal action
  ///
  /// In en, this message translates to:
  /// **'Seal'**
  String get sealAction;

  /// Label for the verify action
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verifyAction;

  /// Label for the extract action
  ///
  /// In en, this message translates to:
  /// **'Extract'**
  String get extractAction;

  /// Label for the inspect action
  ///
  /// In en, this message translates to:
  /// **'Inspect'**
  String get inspectAction;

  /// Title for the settings screen
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Hint text shown in the drag and drop zone
  ///
  /// In en, this message translates to:
  /// **'Drop a file here to seal, or a .zgl file to verify'**
  String get dropZoneHint;

  /// Label for the master key input
  ///
  /// In en, this message translates to:
  /// **'Master Key'**
  String get keyLabel;

  /// Hint text for the key input field
  ///
  /// In en, this message translates to:
  /// **'Enter 64-character hex key or load from file'**
  String get keyHint;

  /// Button label to generate a new key
  ///
  /// In en, this message translates to:
  /// **'Generate New Key'**
  String get generateKeyAction;

  /// Message shown when a file is selected
  ///
  /// In en, this message translates to:
  /// **'File selected: {filename}'**
  String fileSelected(String filename);

  /// Message shown after successful sealing
  ///
  /// In en, this message translates to:
  /// **'File sealed successfully'**
  String get sealSuccess;

  /// Message shown when file verification passes
  ///
  /// In en, this message translates to:
  /// **'File integrity verified - INTACT'**
  String get verifyValid;

  /// Message shown when file has been tampered with
  ///
  /// In en, this message translates to:
  /// **'TAMPERED - File has been modified!'**
  String get verifyTampered;

  /// Message shown when file has expired
  ///
  /// In en, this message translates to:
  /// **'EXPIRED - File has passed its expiration date'**
  String get verifyExpired;

  /// Message shown after successful extraction
  ///
  /// In en, this message translates to:
  /// **'Original file extracted successfully'**
  String get extractSuccess;

  /// Label for the redact action
  ///
  /// In en, this message translates to:
  /// **'Redact Blocks'**
  String get redactAction;

  /// Label for the split key action
  ///
  /// In en, this message translates to:
  /// **'Split Key'**
  String get splitKeyAction;

  /// Label for the selective disclosure action
  ///
  /// In en, this message translates to:
  /// **'Selective Disclosure'**
  String get disclosureAction;

  /// Label for the attestation action
  ///
  /// In en, this message translates to:
  /// **'Add Attestation'**
  String get attestAction;

  /// Title for the audit trail section
  ///
  /// In en, this message translates to:
  /// **'Audit Trail'**
  String get auditTrailTitle;

  /// Message when no file has been selected
  ///
  /// In en, this message translates to:
  /// **'No file selected'**
  String get noFileSelected;

  /// Generic error message
  ///
  /// In en, this message translates to:
  /// **'An error occurred: {message}'**
  String errorGeneric(String message);

  /// Title for the saved keys section
  ///
  /// In en, this message translates to:
  /// **'Saved Keys'**
  String get savedKeysTitle;

  /// Label for the language selector
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// Label for the block size setting
  ///
  /// In en, this message translates to:
  /// **'Default Block Size'**
  String get blockSizeLabel;

  /// Label for the compression toggle
  ///
  /// In en, this message translates to:
  /// **'Enable Compression'**
  String get compressionLabel;

  /// Label for the expiration date picker
  ///
  /// In en, this message translates to:
  /// **'Expiration Date'**
  String get expirationLabel;

  /// Label for the recipient ID input
  ///
  /// In en, this message translates to:
  /// **'Recipient ID'**
  String get recipientLabel;

  /// Label for the threshold input in split-key
  ///
  /// In en, this message translates to:
  /// **'Threshold (M)'**
  String get thresholdLabel;

  /// Label for the total shares input in split-key
  ///
  /// In en, this message translates to:
  /// **'Total Shares (N)'**
  String get totalSharesLabel;

  /// Label for cancel button
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelAction;

  /// Label for select file button
  ///
  /// In en, this message translates to:
  /// **'Select File'**
  String get selectFileAction;

  /// Label for select folder button
  ///
  /// In en, this message translates to:
  /// **'Select Folder'**
  String get selectFolderAction;

  /// Message when no folder has been selected
  ///
  /// In en, this message translates to:
  /// **'No folder selected'**
  String get noFolderSelected;

  /// Drawer section header for core features
  ///
  /// In en, this message translates to:
  /// **'Core'**
  String get drawerCoreSection;

  /// Drawer section header for security features
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get drawerSecuritySection;

  /// Drawer section header for disclosure features
  ///
  /// In en, this message translates to:
  /// **'Disclosure'**
  String get drawerDisclosureSection;

  /// Drawer section header for advanced features
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get drawerAdvancedSection;

  /// Title for the batch operations screen
  ///
  /// In en, this message translates to:
  /// **'Batch Operations'**
  String get batchOperationsTitle;

  /// Tab label for batch verify
  ///
  /// In en, this message translates to:
  /// **'Batch Verify'**
  String get batchVerifyTab;

  /// Tab label for batch seal
  ///
  /// In en, this message translates to:
  /// **'Batch Seal'**
  String get batchSealTab;

  /// Label for input folder selection
  ///
  /// In en, this message translates to:
  /// **'Input Folder'**
  String get batchInputFolder;

  /// Label for output folder selection
  ///
  /// In en, this message translates to:
  /// **'Output Folder'**
  String get batchOutputFolder;

  /// Label for batch options section
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get batchOptions;

  /// Button to start batch verification
  ///
  /// In en, this message translates to:
  /// **'Start Batch Verify'**
  String get batchStartVerify;

  /// Button to start batch sealing
  ///
  /// In en, this message translates to:
  /// **'Start Batch Seal'**
  String get batchStartSeal;

  /// Label shown during batch processing
  ///
  /// In en, this message translates to:
  /// **'Processing...'**
  String get batchProcessing;

  /// Label for batch results section
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get batchResults;

  /// Summary label for verified files
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get batchVerified;

  /// Summary label for sealed files
  ///
  /// In en, this message translates to:
  /// **'Sealed'**
  String get batchSealed;

  /// Summary label for failed files
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get batchFailed;

  /// Summary label for total processing time
  ///
  /// In en, this message translates to:
  /// **'Total Time'**
  String get batchTotalTime;

  /// Title for the classification screen
  ///
  /// In en, this message translates to:
  /// **'Classification'**
  String get classificationTitle;

  /// Label for file picker in classification screen
  ///
  /// In en, this message translates to:
  /// **'Classified File'**
  String get classificationFileLabel;

  /// Label for current classification level
  ///
  /// In en, this message translates to:
  /// **'Current level:'**
  String get classificationCurrentLabel;

  /// Shown when no classification is set
  ///
  /// In en, this message translates to:
  /// **'No classification set'**
  String get classificationNone;

  /// Section label for setting classification
  ///
  /// In en, this message translates to:
  /// **'Set Classification'**
  String get classificationSetLabel;

  /// Button label to set classification
  ///
  /// In en, this message translates to:
  /// **'Set Classification'**
  String get classificationSetAction;

  /// Dropdown label for classification level
  ///
  /// In en, this message translates to:
  /// **'Classification Level'**
  String get classificationLevelLabel;

  /// Input label for classification authority
  ///
  /// In en, this message translates to:
  /// **'Authority'**
  String get classificationAuthorityLabel;

  /// Hint for authority input
  ///
  /// In en, this message translates to:
  /// **'e.g. Security Officer'**
  String get classificationAuthorityHint;

  /// Input label for classification caveat
  ///
  /// In en, this message translates to:
  /// **'Caveat'**
  String get classificationCaveatLabel;

  /// Hint for caveat input
  ///
  /// In en, this message translates to:
  /// **'e.g. NOFORN, EYES ONLY'**
  String get classificationCaveatHint;

  /// Section label for declassification
  ///
  /// In en, this message translates to:
  /// **'Declassify'**
  String get classificationDeclassifyLabel;

  /// Dropdown label for new classification level
  ///
  /// In en, this message translates to:
  /// **'New Level'**
  String get classificationNewLevelLabel;

  /// Button label to declassify
  ///
  /// In en, this message translates to:
  /// **'Declassify'**
  String get classificationDeclassifyAction;

  /// Hint for declassification authority
  ///
  /// In en, this message translates to:
  /// **'e.g. Declassification Authority'**
  String get classificationDeclassifyAuthorityHint;

  /// Title for declassification warning dialog
  ///
  /// In en, this message translates to:
  /// **'Confirm Declassification'**
  String get classificationDeclassifyWarningTitle;

  /// Body text for declassification warning dialog
  ///
  /// In en, this message translates to:
  /// **'Declassification will lower the security level of this document. This action is recorded in the audit trail and cannot be undone. Continue?'**
  String get classificationDeclassifyWarningBody;

  /// Public classification label
  ///
  /// In en, this message translates to:
  /// **'PUBLIC'**
  String get classificationPublic;

  /// Internal classification label
  ///
  /// In en, this message translates to:
  /// **'INTERNAL'**
  String get classificationInternal;

  /// Confidential classification label
  ///
  /// In en, this message translates to:
  /// **'CONFIDENTIAL'**
  String get classificationConfidential;

  /// Secret classification label
  ///
  /// In en, this message translates to:
  /// **'SECRET'**
  String get classificationSecret;

  /// Top Secret classification label
  ///
  /// In en, this message translates to:
  /// **'TOP SECRET'**
  String get classificationTopSecret;

  /// Title for the manifest screen
  ///
  /// In en, this message translates to:
  /// **'Manifests'**
  String get manifestTitle;

  /// Tab label for creating manifests
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get manifestCreateTab;

  /// Tab label for verifying manifests
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get manifestVerifyTab;

  /// Label for the manifest file list
  ///
  /// In en, this message translates to:
  /// **'Files in Manifest'**
  String get manifestFilesLabel;

  /// Button to add a file to manifest
  ///
  /// In en, this message translates to:
  /// **'Add File'**
  String get manifestAddFile;

  /// Shown when no files are in the manifest
  ///
  /// In en, this message translates to:
  /// **'No files added. Tap + to add files.'**
  String get manifestNoFiles;

  /// Label for signer ID input
  ///
  /// In en, this message translates to:
  /// **'Signer ID'**
  String get manifestSignerIdLabel;

  /// Hint for signer ID input
  ///
  /// In en, this message translates to:
  /// **'e.g. auditor@example.com'**
  String get manifestSignerIdHint;

  /// Button to create the manifest
  ///
  /// In en, this message translates to:
  /// **'Create Manifest'**
  String get manifestCreateAction;

  /// Label shown while creating manifest
  ///
  /// In en, this message translates to:
  /// **'Creating...'**
  String get manifestCreating;

  /// Label for manifest file picker
  ///
  /// In en, this message translates to:
  /// **'Manifest File'**
  String get manifestFileLabel;

  /// Label for optional file directory
  ///
  /// In en, this message translates to:
  /// **'File Directory (optional)'**
  String get manifestFileDirectoryLabel;

  /// Hint for file directory picker
  ///
  /// In en, this message translates to:
  /// **'Directory containing the manifest files for verification'**
  String get manifestFileDirectoryHint;

  /// Button to verify the manifest
  ///
  /// In en, this message translates to:
  /// **'Verify Manifest'**
  String get manifestVerifyAction;

  /// Label shown while verifying manifest
  ///
  /// In en, this message translates to:
  /// **'Verifying...'**
  String get manifestVerifying;

  /// Label for manifest verification results
  ///
  /// In en, this message translates to:
  /// **'Verification Results'**
  String get manifestResultsLabel;

  /// Title for the excerpt proof screen
  ///
  /// In en, this message translates to:
  /// **'Excerpt Proof'**
  String get excerptTitle;

  /// Tab label for generating excerpt proofs
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get excerptGenerateTab;

  /// Tab label for verifying excerpt proofs
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get excerptVerifyTab;

  /// Label for excerpt source file picker
  ///
  /// In en, this message translates to:
  /// **'Source File (.zgl)'**
  String get excerptFileLabel;

  /// Button to load blocks from file
  ///
  /// In en, this message translates to:
  /// **'Load Blocks'**
  String get excerptLoadBlocks;

  /// Label for block selection section
  ///
  /// In en, this message translates to:
  /// **'Select Blocks'**
  String get excerptSelectBlocks;

  /// Button to generate excerpt proof
  ///
  /// In en, this message translates to:
  /// **'Generate Proof'**
  String get excerptGenerateAction;

  /// Label shown while generating proof
  ///
  /// In en, this message translates to:
  /// **'Generating...'**
  String get excerptGenerating;

  /// Label for .zgl file picker in verify tab
  ///
  /// In en, this message translates to:
  /// **'Zegel File (.zgl)'**
  String get excerptZglFileLabel;

  /// Label for proof file picker
  ///
  /// In en, this message translates to:
  /// **'Proof File (.json)'**
  String get excerptProofFileLabel;

  /// Button to verify excerpt proof
  ///
  /// In en, this message translates to:
  /// **'Verify Proof'**
  String get excerptVerifyAction;

  /// Label shown while verifying proof
  ///
  /// In en, this message translates to:
  /// **'Verifying...'**
  String get excerptVerifying;

  /// Status when excerpt proof is valid
  ///
  /// In en, this message translates to:
  /// **'Excerpt proof is VALID'**
  String get excerptProofValid;

  /// Status when excerpt proof is invalid
  ///
  /// In en, this message translates to:
  /// **'Excerpt proof is INVALID'**
  String get excerptProofInvalid;

  /// Title for the provenance screen
  ///
  /// In en, this message translates to:
  /// **'Provenance'**
  String get provenanceTitle;

  /// Label for provenance file picker
  ///
  /// In en, this message translates to:
  /// **'File to Inspect'**
  String get provenanceFileLabel;

  /// Button to load provenance data
  ///
  /// In en, this message translates to:
  /// **'Load Provenance'**
  String get provenanceLoadAction;

  /// Label shown while loading provenance
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get provenanceLoading;

  /// Title for the provenance timeline
  ///
  /// In en, this message translates to:
  /// **'Provenance Timeline'**
  String get provenanceTimeline;

  /// Shown when no provenance events exist
  ///
  /// In en, this message translates to:
  /// **'No provenance events found.'**
  String get provenanceNoEvents;

  /// Button to export provenance report
  ///
  /// In en, this message translates to:
  /// **'Export Report'**
  String get provenanceExportReport;

  /// Title for the credential screen
  ///
  /// In en, this message translates to:
  /// **'Credentials'**
  String get credentialTitle;

  /// Tab label for issuing credentials
  ///
  /// In en, this message translates to:
  /// **'Issue'**
  String get credentialIssueTab;

  /// Tab label for verifying credentials
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get credentialVerifyTab;

  /// Label for certificate document picker
  ///
  /// In en, this message translates to:
  /// **'Certificate Document'**
  String get credentialDocumentLabel;

  /// Label for institution details section
  ///
  /// In en, this message translates to:
  /// **'Institution Details'**
  String get credentialInstitutionLabel;

  /// Label for institution name input
  ///
  /// In en, this message translates to:
  /// **'Institution Name'**
  String get credentialInstitutionNameLabel;

  /// Hint for institution name
  ///
  /// In en, this message translates to:
  /// **'e.g. University of Amsterdam'**
  String get credentialInstitutionNameHint;

  /// Label for institution ID input
  ///
  /// In en, this message translates to:
  /// **'Institution ID'**
  String get credentialInstitutionIdLabel;

  /// Hint for institution ID
  ///
  /// In en, this message translates to:
  /// **'e.g. NL-UVA-001'**
  String get credentialInstitutionIdHint;

  /// Label for credential type dropdown
  ///
  /// In en, this message translates to:
  /// **'Credential Type'**
  String get credentialTypeLabel;

  /// Credential type: diploma
  ///
  /// In en, this message translates to:
  /// **'Diploma'**
  String get credentialTypeDiploma;

  /// Credential type: certificate
  ///
  /// In en, this message translates to:
  /// **'Certificate'**
  String get credentialTypeCertificate;

  /// Credential type: license
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get credentialTypeLicense;

  /// Credential type: accreditation
  ///
  /// In en, this message translates to:
  /// **'Accreditation'**
  String get credentialTypeAccreditation;

  /// Label for recipient section
  ///
  /// In en, this message translates to:
  /// **'Recipient'**
  String get credentialRecipientLabel;

  /// Label for recipient name input
  ///
  /// In en, this message translates to:
  /// **'Recipient Name'**
  String get credentialRecipientNameLabel;

  /// Hint for recipient name
  ///
  /// In en, this message translates to:
  /// **'e.g. Jan de Vries'**
  String get credentialRecipientNameHint;

  /// Label for recipient ID input
  ///
  /// In en, this message translates to:
  /// **'Recipient ID'**
  String get credentialRecipientIdLabel;

  /// Hint for recipient ID
  ///
  /// In en, this message translates to:
  /// **'e.g. student number or national ID'**
  String get credentialRecipientIdHint;

  /// Button to issue the credential
  ///
  /// In en, this message translates to:
  /// **'Issue Credential'**
  String get credentialIssueAction;

  /// Label shown while issuing credential
  ///
  /// In en, this message translates to:
  /// **'Issuing...'**
  String get credentialIssuing;

  /// Label for credential file picker
  ///
  /// In en, this message translates to:
  /// **'Credential File (.zgl)'**
  String get credentialFileLabel;

  /// Button to verify the credential
  ///
  /// In en, this message translates to:
  /// **'Verify Credential'**
  String get credentialVerifyAction;

  /// Label shown while verifying credential
  ///
  /// In en, this message translates to:
  /// **'Verifying...'**
  String get credentialVerifying;

  /// Label for credential details section
  ///
  /// In en, this message translates to:
  /// **'Credential Details'**
  String get credentialDetailsLabel;

  /// Label for credential issue date
  ///
  /// In en, this message translates to:
  /// **'Issued At'**
  String get credentialIssuedAtLabel;

  /// Status when credential is valid
  ///
  /// In en, this message translates to:
  /// **'Credential is VALID - all attestations verified'**
  String get credentialValidStatus;

  /// Status when credential is invalid
  ///
  /// In en, this message translates to:
  /// **'Credential is INVALID - attestation verification failed'**
  String get credentialInvalidStatus;

  /// Title for the contract workflow screen
  ///
  /// In en, this message translates to:
  /// **'Contract Workflow'**
  String get contractTitle;

  /// Label for contract document picker
  ///
  /// In en, this message translates to:
  /// **'Contract Document'**
  String get contractDocumentLabel;

  /// Label for the contract owner key
  ///
  /// In en, this message translates to:
  /// **'Owner Key'**
  String get contractOwnerKeyLabel;

  /// Label for contract parties section
  ///
  /// In en, this message translates to:
  /// **'Contract Parties'**
  String get contractPartiesLabel;

  /// Shown when no parties are added
  ///
  /// In en, this message translates to:
  /// **'No parties added. Tap the + button to add parties.'**
  String get contractNoParties;

  /// Button to add a contract party
  ///
  /// In en, this message translates to:
  /// **'Add Party'**
  String get contractAddParty;

  /// Action button in add party dialog
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get contractAddPartyAction;

  /// Label for party name input
  ///
  /// In en, this message translates to:
  /// **'Party Name'**
  String get contractPartyName;

  /// Hint for party name
  ///
  /// In en, this message translates to:
  /// **'e.g. Jane Smith'**
  String get contractPartyNameHint;

  /// Label for party role dropdown
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get contractPartyRole;

  /// Label for party key input
  ///
  /// In en, this message translates to:
  /// **'Party Key (hex)'**
  String get contractPartyKey;

  /// Hint for party key
  ///
  /// In en, this message translates to:
  /// **'64-character hex key (optional)'**
  String get contractPartyKeyHint;

  /// Label for split key config section
  ///
  /// In en, this message translates to:
  /// **'Split Key Configuration'**
  String get contractSplitKeyLabel;

  /// Toggle for split key in contracts
  ///
  /// In en, this message translates to:
  /// **'Enable Multi-Party Key Splitting'**
  String get contractEnableSplitKey;

  /// Label for contract workflow section
  ///
  /// In en, this message translates to:
  /// **'Workflow Steps'**
  String get contractWorkflowLabel;

  /// Button to seal the contract
  ///
  /// In en, this message translates to:
  /// **'Seal Contract'**
  String get contractSealAction;

  /// Button to verify all attestations
  ///
  /// In en, this message translates to:
  /// **'Verify Attestations'**
  String get contractVerifyAttestations;

  /// Label for default classification setting
  ///
  /// In en, this message translates to:
  /// **'Default Classification Level'**
  String get settingsDefaultClassification;

  /// Label for TSA URL setting
  ///
  /// In en, this message translates to:
  /// **'Timestamp Authority (TSA) URL'**
  String get settingsTsaUrl;

  /// Hint for TSA URL input
  ///
  /// In en, this message translates to:
  /// **'e.g. https://tsa.example.com/timestamp'**
  String get settingsTsaUrlHint;

  /// Label for advanced options section
  ///
  /// In en, this message translates to:
  /// **'Advanced Options'**
  String get settingsAdvancedOptions;

  /// Toggle label for media metadata preservation
  ///
  /// In en, this message translates to:
  /// **'Preserve Media Metadata'**
  String get settingsPreserveMediaMetadata;

  /// Description for media metadata preservation toggle
  ///
  /// In en, this message translates to:
  /// **'Keep EXIF, XMP, and other media metadata when sealing'**
  String get settingsPreserveMediaMetadataDesc;

  /// Toggle label for anonymous mode
  ///
  /// In en, this message translates to:
  /// **'Anonymous Mode'**
  String get settingsAnonymousMode;

  /// Description for anonymous mode toggle
  ///
  /// In en, this message translates to:
  /// **'Omit user identity from audit trail and provenance records'**
  String get settingsAnonymousModeDesc;

  /// Label for anonymous mode in seal screen
  ///
  /// In en, this message translates to:
  /// **'Anonymous Mode'**
  String get sealAnonymousMode;

  /// Description for anonymous mode in seal screen
  ///
  /// In en, this message translates to:
  /// **'Omit identity from audit trail'**
  String get sealAnonymousModeDesc;

  /// Label for classification dropdown in seal screen
  ///
  /// In en, this message translates to:
  /// **'Classification Level'**
  String get sealClassificationLevel;

  /// Label for classification authority in seal screen
  ///
  /// In en, this message translates to:
  /// **'Classification Authority'**
  String get sealClassificationAuthority;

  /// Hint for classification authority input
  ///
  /// In en, this message translates to:
  /// **'e.g. Security Officer'**
  String get sealClassificationAuthorityHint;

  /// Label for regulatory hold date picker
  ///
  /// In en, this message translates to:
  /// **'Regulatory Hold Date'**
  String get sealRegulatoryHold;

  /// Shown when a value is not set
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get sealNotSet;

  /// Label for TSA URL in seal screen
  ///
  /// In en, this message translates to:
  /// **'TSA URL'**
  String get sealTsaUrl;

  /// Hint for TSA URL
  ///
  /// In en, this message translates to:
  /// **'Timestamp authority URL for trusted timestamps'**
  String get sealTsaUrlHint;

  /// Label for media metadata toggle in seal screen
  ///
  /// In en, this message translates to:
  /// **'Preserve Media Metadata'**
  String get sealPreserveMediaMetadata;

  /// Description for media metadata toggle
  ///
  /// In en, this message translates to:
  /// **'Keep EXIF/XMP data in sealed file'**
  String get sealPreserveMediaMetadataDesc;

  /// Label for classification display in verify screen
  ///
  /// In en, this message translates to:
  /// **'Classification'**
  String get verifyClassificationLabel;

  /// Regulatory hold status display
  ///
  /// In en, this message translates to:
  /// **'HELD UNTIL {date}'**
  String verifyRegulatoryHold(String date);

  /// Label for timestamp authority in verify screen
  ///
  /// In en, this message translates to:
  /// **'Timestamp Authority:'**
  String get verifyTimestampAuthority;

  /// Label for attestation policy check
  ///
  /// In en, this message translates to:
  /// **'Attestation Policy'**
  String get verifyAttestationPolicy;

  /// Shown when all attestations are valid
  ///
  /// In en, this message translates to:
  /// **'All attestations verified'**
  String get verifyAllAttestationsValid;

  /// Shown when some attestations fail
  ///
  /// In en, this message translates to:
  /// **'Some attestations not verified'**
  String get verifySomeAttestationsInvalid;

  /// Label for collapsible provenance timeline
  ///
  /// In en, this message translates to:
  /// **'Provenance Timeline'**
  String get verifyProvenancePreview;

  /// Help text for batch verify
  ///
  /// In en, this message translates to:
  /// **'Verify all .zgl files in a folder at once'**
  String get helpBatchVerify;

  /// Help text for batch seal
  ///
  /// In en, this message translates to:
  /// **'Seal all files in a folder into .zgl format'**
  String get helpBatchSeal;

  /// Help text for classification screen
  ///
  /// In en, this message translates to:
  /// **'Set or change the security classification of a sealed file'**
  String get helpClassification;

  /// Help text for manifest screen
  ///
  /// In en, this message translates to:
  /// **'Create or verify a signed list of sealed files'**
  String get helpManifest;

  /// Help text for excerpt proof screen
  ///
  /// In en, this message translates to:
  /// **'Generate or verify cryptographic proofs for specific blocks'**
  String get helpExcerpt;

  /// Help text for provenance screen
  ///
  /// In en, this message translates to:
  /// **'View the chain of custody and provenance events'**
  String get helpProvenance;

  /// Help text for credential screen
  ///
  /// In en, this message translates to:
  /// **'Issue or verify academic credentials and certifications'**
  String get helpCredential;

  /// Help text for contract screen
  ///
  /// In en, this message translates to:
  /// **'Multi-party contract workflow with attestations and split keys'**
  String get helpContract;

  /// Title for the inspect screen
  ///
  /// In en, this message translates to:
  /// **'Inspect'**
  String get inspectTitle;

  /// Label for inspect file picker
  ///
  /// In en, this message translates to:
  /// **'File to Inspect'**
  String get inspectFileLabel;

  /// Help text for inspect screen
  ///
  /// In en, this message translates to:
  /// **'View file header information without the master key'**
  String get helpInspect;

  /// Title for the media metadata screen
  ///
  /// In en, this message translates to:
  /// **'Media Metadata'**
  String get mediaMetadataTitle;

  /// Label for media file picker
  ///
  /// In en, this message translates to:
  /// **'Media File (.zgl)'**
  String get mediaMetadataFileLabel;

  /// Button to load media metadata
  ///
  /// In en, this message translates to:
  /// **'Load Metadata'**
  String get mediaMetadataLoadAction;

  /// Help text for media metadata screen
  ///
  /// In en, this message translates to:
  /// **'View EXIF, GPS, and other media metadata from sealed files'**
  String get helpMediaMetadata;

  /// Title for the timestamp screen
  ///
  /// In en, this message translates to:
  /// **'Timestamps'**
  String get timestampTitle;

  /// Tab label for creating timestamps
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get timestampCreateTab;

  /// Tab label for verifying timestamps
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get timestampVerifyTab;

  /// Label for timestamp file picker
  ///
  /// In en, this message translates to:
  /// **'File to Timestamp'**
  String get timestampFileLabel;

  /// Button to create a timestamp
  ///
  /// In en, this message translates to:
  /// **'Create Timestamp'**
  String get timestampCreateAction;

  /// Button to verify a timestamp
  ///
  /// In en, this message translates to:
  /// **'Verify Timestamp'**
  String get timestampVerifyAction;

  /// Help text for timestamp screen
  ///
  /// In en, this message translates to:
  /// **'Request or verify trusted timestamps from a TSA'**
  String get helpTimestamp;

  /// Title for the version chain screen
  ///
  /// In en, this message translates to:
  /// **'Version Chain'**
  String get versionChainTitle;

  /// Label for version chain file list
  ///
  /// In en, this message translates to:
  /// **'Version Files'**
  String get versionChainFileLabel;

  /// Button to add a file to version chain
  ///
  /// In en, this message translates to:
  /// **'Add File'**
  String get versionChainAddFile;

  /// Button to verify the version chain
  ///
  /// In en, this message translates to:
  /// **'Verify Version Chain'**
  String get versionChainVerifyAction;

  /// Status when version chain is valid
  ///
  /// In en, this message translates to:
  /// **'Version Chain VALID'**
  String get versionChainValid;

  /// Status when version chain is broken
  ///
  /// In en, this message translates to:
  /// **'Version Chain BROKEN'**
  String get versionChainInvalid;

  /// Help text for version chain screen
  ///
  /// In en, this message translates to:
  /// **'View and verify version history and chain hashes'**
  String get helpVersionChain;

  /// Drawer section header for tools
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get drawerToolsSection;
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
      <String>['en', 'nl'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'nl':
      return AppLocalizationsNl();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
