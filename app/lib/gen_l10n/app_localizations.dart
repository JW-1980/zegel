import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_nl.dart';

abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('nl'),
  ];

  String get appTitle;
  String get homeTitle;
  String get sealAction;
  String get verifyAction;
  String get extractAction;
  String get inspectAction;
  String get settingsTitle;
  String get dropZoneHint;
  String get keyLabel;
  String get keyHint;
  String get generateKeyAction;
  String fileSelected(String filename);
  String get sealSuccess;
  String get verifyValid;
  String get verifyTampered;
  String get verifyExpired;
  String get extractSuccess;
  String get redactAction;
  String get splitKeyAction;
  String get disclosureAction;
  String get attestAction;
  String get auditTrailTitle;
  String get noFileSelected;
  String errorGeneric(String message);
  String get savedKeysTitle;
  String get languageLabel;
  String get blockSizeLabel;
  String get compressionLabel;
  String get expirationLabel;
  String get recipientLabel;
  String get thresholdLabel;
  String get totalSharesLabel;
  String get cancelAction;
  String get selectFileAction;
  String get selectFolderAction;
  String get noFolderSelected;
  String get drawerCoreSection;
  String get drawerSecuritySection;
  String get drawerDisclosureSection;
  String get drawerAdvancedSection;
  String get batchOperationsTitle;
  String get batchVerifyTab;
  String get batchSealTab;
  String get batchInputFolder;
  String get batchOutputFolder;
  String get batchOptions;
  String get batchStartVerify;
  String get batchStartSeal;
  String get batchProcessing;
  String get batchResults;
  String get batchVerified;
  String get batchSealed;
  String get batchFailed;
  String get batchTotalTime;
  String get classificationTitle;
  String get classificationFileLabel;
  String get classificationCurrentLabel;
  String get classificationNone;
  String get classificationSetLabel;
  String get classificationSetAction;
  String get classificationLevelLabel;
  String get classificationAuthorityLabel;
  String get classificationAuthorityHint;
  String get classificationCaveatLabel;
  String get classificationCaveatHint;
  String get classificationDeclassifyLabel;
  String get classificationNewLevelLabel;
  String get classificationDeclassifyAction;
  String get classificationDeclassifyAuthorityHint;
  String get classificationDeclassifyWarningTitle;
  String get classificationDeclassifyWarningBody;
  String get classificationPublic;
  String get classificationInternal;
  String get classificationConfidential;
  String get classificationSecret;
  String get classificationTopSecret;
  String get manifestTitle;
  String get manifestCreateTab;
  String get manifestVerifyTab;
  String get manifestFilesLabel;
  String get manifestAddFile;
  String get manifestNoFiles;
  String get manifestSignerIdLabel;
  String get manifestSignerIdHint;
  String get manifestCreateAction;
  String get manifestCreating;
  String get manifestFileLabel;
  String get manifestFileDirectoryLabel;
  String get manifestFileDirectoryHint;
  String get manifestVerifyAction;
  String get manifestVerifying;
  String get manifestResultsLabel;
  String get excerptTitle;
  String get excerptGenerateTab;
  String get excerptVerifyTab;
  String get excerptFileLabel;
  String get excerptLoadBlocks;
  String get excerptSelectBlocks;
  String get excerptGenerateAction;
  String get excerptGenerating;
  String get excerptZglFileLabel;
  String get excerptProofFileLabel;
  String get excerptVerifyAction;
  String get excerptVerifying;
  String get excerptProofValid;
  String get excerptProofInvalid;
  String get provenanceTitle;
  String get provenanceFileLabel;
  String get provenanceLoadAction;
  String get provenanceLoading;
  String get provenanceTimeline;
  String get provenanceNoEvents;
  String get provenanceExportReport;
  String get credentialTitle;
  String get credentialIssueTab;
  String get credentialVerifyTab;
  String get credentialDocumentLabel;
  String get credentialInstitutionLabel;
  String get credentialInstitutionNameLabel;
  String get credentialInstitutionNameHint;
  String get credentialInstitutionIdLabel;
  String get credentialInstitutionIdHint;
  String get credentialTypeLabel;
  String get credentialTypeDiploma;
  String get credentialTypeCertificate;
  String get credentialTypeLicense;
  String get credentialTypeAccreditation;
  String get credentialRecipientLabel;
  String get credentialRecipientNameLabel;
  String get credentialRecipientNameHint;
  String get credentialRecipientIdLabel;
  String get credentialRecipientIdHint;
  String get credentialIssueAction;
  String get credentialIssuing;
  String get credentialFileLabel;
  String get credentialVerifyAction;
  String get credentialVerifying;
  String get credentialDetailsLabel;
  String get credentialIssuedAtLabel;
  String get credentialValidStatus;
  String get credentialInvalidStatus;
  String get contractTitle;
  String get contractDocumentLabel;
  String get contractOwnerKeyLabel;
  String get contractPartiesLabel;
  String get contractNoParties;
  String get contractAddParty;
  String get contractAddPartyAction;
  String get contractPartyName;
  String get contractPartyNameHint;
  String get contractPartyRole;
  String get contractPartyKey;
  String get contractPartyKeyHint;
  String get contractSplitKeyLabel;
  String get contractEnableSplitKey;
  String get contractWorkflowLabel;
  String get contractSealAction;
  String get contractVerifyAttestations;
  String get settingsDefaultClassification;
  String get settingsTsaUrl;
  String get settingsTsaUrlHint;
  String get settingsAdvancedOptions;
  String get settingsPreserveMediaMetadata;
  String get settingsPreserveMediaMetadataDesc;
  String get settingsAnonymousMode;
  String get settingsAnonymousModeDesc;
  String get sealAnonymousMode;
  String get sealAnonymousModeDesc;
  String get sealClassificationLevel;
  String get sealClassificationAuthority;
  String get sealClassificationAuthorityHint;
  String get sealRegulatoryHold;
  String get sealNotSet;
  String get sealTsaUrl;
  String get sealTsaUrlHint;
  String get sealPreserveMediaMetadata;
  String get sealPreserveMediaMetadataDesc;
  String get verifyClassificationLabel;
  String verifyRegulatoryHold(String date);
  String get verifyTimestampAuthority;
  String get verifyAttestationPolicy;
  String get verifyAllAttestationsValid;
  String get verifySomeAttestationsInvalid;
  String get verifyProvenancePreview;
  String get helpBatchVerify;
  String get helpBatchSeal;
  String get helpClassification;
  String get helpManifest;
  String get helpExcerpt;
  String get helpProvenance;
  String get helpCredential;
  String get helpContract;
  String get inspectTitle;
  String get inspectFileLabel;
  String get helpInspect;
  String get mediaMetadataTitle;
  String get mediaMetadataFileLabel;
  String get mediaMetadataLoadAction;
  String get helpMediaMetadata;
  String get timestampTitle;
  String get timestampCreateTab;
  String get timestampVerifyTab;
  String get timestampFileLabel;
  String get timestampCreateAction;
  String get timestampVerifyAction;
  String get helpTimestamp;
  String get versionChainTitle;
  String get versionChainFileLabel;
  String get versionChainAddFile;
  String get versionChainVerifyAction;
  String get versionChainValid;
  String get versionChainInvalid;
  String get helpVersionChain;
  String get drawerToolsSection;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(
        lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'nl'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  switch (locale.languageCode) {
    case 'nl':
      return AppLocalizationsNl();
    case 'en':
    default:
      return AppLocalizationsEn();
  }
}
