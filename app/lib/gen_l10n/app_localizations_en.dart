// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Zegel';

  @override
  String get homeTitle => 'Zegel - Tamper-Proof Sealing';

  @override
  String get sealAction => 'Seal';

  @override
  String get verifyAction => 'Verify';

  @override
  String get extractAction => 'Extract';

  @override
  String get inspectAction => 'Inspect';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get dropZoneHint =>
      'Drop a file here to seal, or a .zgl file to verify';

  @override
  String get keyLabel => 'Master Key';

  @override
  String get keyHint => 'Enter 64-character hex key or load from file';

  @override
  String get generateKeyAction => 'Generate New Key';

  @override
  String fileSelected(String filename) {
    return 'File selected: $filename';
  }

  @override
  String get sealSuccess => 'File sealed successfully';

  @override
  String get verifyValid => 'File integrity verified - INTACT';

  @override
  String get verifyTampered => 'TAMPERED - File has been modified!';

  @override
  String get verifyExpired => 'EXPIRED - File has passed its expiration date';

  @override
  String get extractSuccess => 'Original file extracted successfully';

  @override
  String get redactAction => 'Redact Blocks';

  @override
  String get splitKeyAction => 'Split Key';

  @override
  String get disclosureAction => 'Selective Disclosure';

  @override
  String get attestAction => 'Add Attestation';

  @override
  String get auditTrailTitle => 'Audit Trail';

  @override
  String get noFileSelected => 'No file selected';

  @override
  String errorGeneric(String message) {
    return 'An error occurred: $message';
  }

  @override
  String get savedKeysTitle => 'Saved Keys';

  @override
  String get languageLabel => 'Language';

  @override
  String get blockSizeLabel => 'Default Block Size';

  @override
  String get compressionLabel => 'Enable Compression';

  @override
  String get expirationLabel => 'Expiration Date';

  @override
  String get recipientLabel => 'Recipient ID';

  @override
  String get thresholdLabel => 'Threshold (M)';

  @override
  String get totalSharesLabel => 'Total Shares (N)';

  @override
  String get cancelAction => 'Cancel';

  @override
  String get selectFileAction => 'Select File';

  @override
  String get selectFolderAction => 'Select Folder';

  @override
  String get noFolderSelected => 'No folder selected';

  @override
  String get drawerCoreSection => 'Core';

  @override
  String get drawerSecuritySection => 'Security';

  @override
  String get drawerDisclosureSection => 'Disclosure';

  @override
  String get drawerAdvancedSection => 'Advanced';

  @override
  String get batchOperationsTitle => 'Batch Operations';

  @override
  String get batchVerifyTab => 'Batch Verify';

  @override
  String get batchSealTab => 'Batch Seal';

  @override
  String get batchInputFolder => 'Input Folder';

  @override
  String get batchOutputFolder => 'Output Folder';

  @override
  String get batchOptions => 'Options';

  @override
  String get batchStartVerify => 'Start Batch Verify';

  @override
  String get batchStartSeal => 'Start Batch Seal';

  @override
  String get batchProcessing => 'Processing...';

  @override
  String get batchResults => 'Results';

  @override
  String get batchVerified => 'Verified';

  @override
  String get batchSealed => 'Sealed';

  @override
  String get batchFailed => 'Failed';

  @override
  String get batchTotalTime => 'Total Time';

  @override
  String get classificationTitle => 'Classification';

  @override
  String get classificationFileLabel => 'Classified File';

  @override
  String get classificationCurrentLabel => 'Current level:';

  @override
  String get classificationNone => 'No classification set';

  @override
  String get classificationSetLabel => 'Set Classification';

  @override
  String get classificationSetAction => 'Set Classification';

  @override
  String get classificationLevelLabel => 'Classification Level';

  @override
  String get classificationAuthorityLabel => 'Authority';

  @override
  String get classificationAuthorityHint => 'e.g. Security Officer';

  @override
  String get classificationCaveatLabel => 'Caveat';

  @override
  String get classificationCaveatHint => 'e.g. NOFORN, EYES ONLY';

  @override
  String get classificationDeclassifyLabel => 'Declassify';

  @override
  String get classificationNewLevelLabel => 'New Level';

  @override
  String get classificationDeclassifyAction => 'Declassify';

  @override
  String get classificationDeclassifyAuthorityHint =>
      'e.g. Declassification Authority';

  @override
  String get classificationDeclassifyWarningTitle => 'Confirm Declassification';

  @override
  String get classificationDeclassifyWarningBody =>
      'Declassification will lower the security level of this document. This action is recorded in the audit trail and cannot be undone. Continue?';

  @override
  String get classificationPublic => 'PUBLIC';

  @override
  String get classificationInternal => 'INTERNAL';

  @override
  String get classificationConfidential => 'CONFIDENTIAL';

  @override
  String get classificationSecret => 'SECRET';

  @override
  String get classificationTopSecret => 'TOP SECRET';

  @override
  String get manifestTitle => 'Manifests';

  @override
  String get manifestCreateTab => 'Create';

  @override
  String get manifestVerifyTab => 'Verify';

  @override
  String get manifestFilesLabel => 'Files in Manifest';

  @override
  String get manifestAddFile => 'Add File';

  @override
  String get manifestNoFiles => 'No files added. Tap + to add files.';

  @override
  String get manifestSignerIdLabel => 'Signer ID';

  @override
  String get manifestSignerIdHint => 'e.g. auditor@example.com';

  @override
  String get manifestCreateAction => 'Create Manifest';

  @override
  String get manifestCreating => 'Creating...';

  @override
  String get manifestFileLabel => 'Manifest File';

  @override
  String get manifestFileDirectoryLabel => 'File Directory (optional)';

  @override
  String get manifestFileDirectoryHint =>
      'Directory containing the manifest files for verification';

  @override
  String get manifestVerifyAction => 'Verify Manifest';

  @override
  String get manifestVerifying => 'Verifying...';

  @override
  String get manifestResultsLabel => 'Verification Results';

  @override
  String get excerptTitle => 'Excerpt Proof';

  @override
  String get excerptGenerateTab => 'Generate';

  @override
  String get excerptVerifyTab => 'Verify';

  @override
  String get excerptFileLabel => 'Source File (.zgl)';

  @override
  String get excerptLoadBlocks => 'Load Blocks';

  @override
  String get excerptSelectBlocks => 'Select Blocks';

  @override
  String get excerptGenerateAction => 'Generate Proof';

  @override
  String get excerptGenerating => 'Generating...';

  @override
  String get excerptZglFileLabel => 'Zegel File (.zgl)';

  @override
  String get excerptProofFileLabel => 'Proof File (.json)';

  @override
  String get excerptVerifyAction => 'Verify Proof';

  @override
  String get excerptVerifying => 'Verifying...';

  @override
  String get excerptProofValid => 'Excerpt proof is VALID';

  @override
  String get excerptProofInvalid => 'Excerpt proof is INVALID';

  @override
  String get provenanceTitle => 'Provenance';

  @override
  String get provenanceFileLabel => 'File to Inspect';

  @override
  String get provenanceLoadAction => 'Load Provenance';

  @override
  String get provenanceLoading => 'Loading...';

  @override
  String get provenanceTimeline => 'Provenance Timeline';

  @override
  String get provenanceNoEvents => 'No provenance events found.';

  @override
  String get provenanceExportReport => 'Export Report';

  @override
  String get credentialTitle => 'Credentials';

  @override
  String get credentialIssueTab => 'Issue';

  @override
  String get credentialVerifyTab => 'Verify';

  @override
  String get credentialDocumentLabel => 'Certificate Document';

  @override
  String get credentialInstitutionLabel => 'Institution Details';

  @override
  String get credentialInstitutionNameLabel => 'Institution Name';

  @override
  String get credentialInstitutionNameHint => 'e.g. University of Amsterdam';

  @override
  String get credentialInstitutionIdLabel => 'Institution ID';

  @override
  String get credentialInstitutionIdHint => 'e.g. NL-UVA-001';

  @override
  String get credentialTypeLabel => 'Credential Type';

  @override
  String get credentialTypeDiploma => 'Diploma';

  @override
  String get credentialTypeCertificate => 'Certificate';

  @override
  String get credentialTypeLicense => 'License';

  @override
  String get credentialTypeAccreditation => 'Accreditation';

  @override
  String get credentialRecipientLabel => 'Recipient';

  @override
  String get credentialRecipientNameLabel => 'Recipient Name';

  @override
  String get credentialRecipientNameHint => 'e.g. Jan de Vries';

  @override
  String get credentialRecipientIdLabel => 'Recipient ID';

  @override
  String get credentialRecipientIdHint => 'e.g. student number or national ID';

  @override
  String get credentialIssueAction => 'Issue Credential';

  @override
  String get credentialIssuing => 'Issuing...';

  @override
  String get credentialFileLabel => 'Credential File (.zgl)';

  @override
  String get credentialVerifyAction => 'Verify Credential';

  @override
  String get credentialVerifying => 'Verifying...';

  @override
  String get credentialDetailsLabel => 'Credential Details';

  @override
  String get credentialIssuedAtLabel => 'Issued At';

  @override
  String get credentialValidStatus =>
      'Credential is VALID - all attestations verified';

  @override
  String get credentialInvalidStatus =>
      'Credential is INVALID - attestation verification failed';

  @override
  String get contractTitle => 'Contract Workflow';

  @override
  String get contractDocumentLabel => 'Contract Document';

  @override
  String get contractOwnerKeyLabel => 'Owner Key';

  @override
  String get contractPartiesLabel => 'Contract Parties';

  @override
  String get contractNoParties =>
      'No parties added. Tap the + button to add parties.';

  @override
  String get contractAddParty => 'Add Party';

  @override
  String get contractAddPartyAction => 'Add';

  @override
  String get contractPartyName => 'Party Name';

  @override
  String get contractPartyNameHint => 'e.g. Jane Smith';

  @override
  String get contractPartyRole => 'Role';

  @override
  String get contractPartyKey => 'Party Key (hex)';

  @override
  String get contractPartyKeyHint => '64-character hex key (optional)';

  @override
  String get contractSplitKeyLabel => 'Split Key Configuration';

  @override
  String get contractEnableSplitKey => 'Enable Multi-Party Key Splitting';

  @override
  String get contractWorkflowLabel => 'Workflow Steps';

  @override
  String get contractSealAction => 'Seal Contract';

  @override
  String get contractVerifyAttestations => 'Verify Attestations';

  @override
  String get settingsDefaultClassification => 'Default Classification Level';

  @override
  String get settingsTsaUrl => 'Timestamp Authority (TSA) URL';

  @override
  String get settingsTsaUrlHint => 'e.g. https://tsa.example.com/timestamp';

  @override
  String get settingsAdvancedOptions => 'Advanced Options';

  @override
  String get settingsPreserveMediaMetadata => 'Preserve Media Metadata';

  @override
  String get settingsPreserveMediaMetadataDesc =>
      'Keep EXIF, XMP, and other media metadata when sealing';

  @override
  String get settingsAnonymousMode => 'Anonymous Mode';

  @override
  String get settingsAnonymousModeDesc =>
      'Omit user identity from audit trail and provenance records';

  @override
  String get sealAnonymousMode => 'Anonymous Mode';

  @override
  String get sealAnonymousModeDesc => 'Omit identity from audit trail';

  @override
  String get sealClassificationLevel => 'Classification Level';

  @override
  String get sealClassificationAuthority => 'Classification Authority';

  @override
  String get sealClassificationAuthorityHint => 'e.g. Security Officer';

  @override
  String get sealRegulatoryHold => 'Regulatory Hold Date';

  @override
  String get sealNotSet => 'Not set';

  @override
  String get sealTsaUrl => 'TSA URL';

  @override
  String get sealTsaUrlHint => 'Timestamp authority URL for trusted timestamps';

  @override
  String get sealPreserveMediaMetadata => 'Preserve Media Metadata';

  @override
  String get sealPreserveMediaMetadataDesc =>
      'Keep EXIF/XMP data in sealed file';

  @override
  String get verifyClassificationLabel => 'Classification';

  @override
  String verifyRegulatoryHold(String date) {
    return 'HELD UNTIL $date';
  }

  @override
  String get verifyTimestampAuthority => 'Timestamp Authority:';

  @override
  String get verifyAttestationPolicy => 'Attestation Policy';

  @override
  String get verifyAllAttestationsValid => 'All attestations verified';

  @override
  String get verifySomeAttestationsInvalid => 'Some attestations not verified';

  @override
  String get verifyProvenancePreview => 'Provenance Timeline';

  @override
  String get helpBatchVerify => 'Verify all .zgl files in a folder at once';

  @override
  String get helpBatchSeal => 'Seal all files in a folder into .zgl format';

  @override
  String get helpClassification =>
      'Set or change the security classification of a sealed file';

  @override
  String get helpManifest => 'Create or verify a signed list of sealed files';

  @override
  String get helpExcerpt =>
      'Generate or verify cryptographic proofs for specific blocks';

  @override
  String get helpProvenance =>
      'View the chain of custody and provenance events';

  @override
  String get helpCredential =>
      'Issue or verify academic credentials and certifications';

  @override
  String get helpContract =>
      'Multi-party contract workflow with attestations and split keys';

  @override
  String get inspectTitle => 'Inspect';

  @override
  String get inspectFileLabel => 'File to Inspect';

  @override
  String get helpInspect =>
      'View file header information without the master key';

  @override
  String get mediaMetadataTitle => 'Media Metadata';

  @override
  String get mediaMetadataFileLabel => 'Media File (.zgl)';

  @override
  String get mediaMetadataLoadAction => 'Load Metadata';

  @override
  String get helpMediaMetadata =>
      'View EXIF, GPS, and other media metadata from sealed files';

  @override
  String get timestampTitle => 'Timestamps';

  @override
  String get timestampCreateTab => 'Create';

  @override
  String get timestampVerifyTab => 'Verify';

  @override
  String get timestampFileLabel => 'File to Timestamp';

  @override
  String get timestampCreateAction => 'Create Timestamp';

  @override
  String get timestampVerifyAction => 'Verify Timestamp';

  @override
  String get helpTimestamp => 'Request or verify trusted timestamps from a TSA';

  @override
  String get versionChainTitle => 'Version Chain';

  @override
  String get versionChainFileLabel => 'Version Files';

  @override
  String get versionChainAddFile => 'Add File';

  @override
  String get versionChainVerifyAction => 'Verify Version Chain';

  @override
  String get versionChainValid => 'Version Chain VALID';

  @override
  String get versionChainInvalid => 'Version Chain BROKEN';

  @override
  String get helpVersionChain =>
      'View and verify version history and chain hashes';

  @override
  String get drawerToolsSection => 'Tools';
}
