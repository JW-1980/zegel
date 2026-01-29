import 'app_localizations.dart';

class AppLocalizationsNl extends AppLocalizations {
  AppLocalizationsNl([super.locale = 'nl']);

  @override
  String get appTitle => 'Zegel';

  @override
  String get homeTitle => 'Zegel - Fraudebestendige Verzegeling';

  @override
  String get sealAction => 'Verzegelen';

  @override
  String get verifyAction => 'Verifi\u00ebren';

  @override
  String get extractAction => 'Uitpakken';

  @override
  String get inspectAction => 'Inspecteren';

  @override
  String get settingsTitle => 'Instellingen';

  @override
  String get dropZoneHint => 'Sleep een bestand hierheen om te verzegelen, of een .zgl bestand om te verifi\u00ebren';

  @override
  String get keyLabel => 'Hoofdsleutel';

  @override
  String get keyHint => 'Voer een 64-teken hexadecimale sleutel in of laad uit bestand';

  @override
  String get generateKeyAction => 'Nieuwe Sleutel Genereren';

  @override
  String fileSelected(String filename) => 'Bestand geselecteerd: $filename';

  @override
  String get sealSuccess => 'Bestand succesvol verzegeld';

  @override
  String get verifyValid => 'Bestandsintegriteit geverifieerd - INTACT';

  @override
  String get verifyTampered => 'GEMANIPULEERD - Bestand is gewijzigd!';

  @override
  String get verifyExpired => 'VERLOPEN - Bestand is voorbij de vervaldatum';

  @override
  String get extractSuccess => 'Origineel bestand succesvol uitgepakt';

  @override
  String get redactAction => 'Blokken Redigeren';

  @override
  String get splitKeyAction => 'Sleutel Splitsen';

  @override
  String get disclosureAction => 'Selectieve Openbaarmaking';

  @override
  String get attestAction => 'Attestatie Toevoegen';

  @override
  String get auditTrailTitle => 'Auditspoor';

  @override
  String get noFileSelected => 'Geen bestand geselecteerd';

  @override
  String errorGeneric(String message) => 'Er is een fout opgetreden: $message';

  @override
  String get savedKeysTitle => 'Opgeslagen Sleutels';

  @override
  String get languageLabel => 'Taal';

  @override
  String get blockSizeLabel => 'Standaard Blokgrootte';

  @override
  String get compressionLabel => 'Compressie Inschakelen';

  @override
  String get expirationLabel => 'Vervaldatum';

  @override
  String get recipientLabel => 'Ontvanger-ID';

  @override
  String get thresholdLabel => 'Drempelwaarde (M)';

  @override
  String get totalSharesLabel => 'Totaal Aantal Delen (N)';

  @override
  String get cancelAction => 'Annuleren';

  @override
  String get selectFileAction => 'Bestand Selecteren';

  @override
  String get selectFolderAction => 'Map Selecteren';

  @override
  String get noFolderSelected => 'Geen map geselecteerd';

  @override
  String get drawerCoreSection => 'Basis';

  @override
  String get drawerSecuritySection => 'Beveiliging';

  @override
  String get drawerDisclosureSection => 'Openbaarmaking';

  @override
  String get drawerAdvancedSection => 'Geavanceerd';

  @override
  String get batchOperationsTitle => 'Batchbewerkingen';

  @override
  String get batchVerifyTab => 'Batch Verifi\u00ebren';

  @override
  String get batchSealTab => 'Batch Verzegelen';

  @override
  String get batchInputFolder => 'Invoermap';

  @override
  String get batchOutputFolder => 'Uitvoermap';

  @override
  String get batchOptions => 'Opties';

  @override
  String get batchStartVerify => 'Batch Verificatie Starten';

  @override
  String get batchStartSeal => 'Batch Verzegeling Starten';

  @override
  String get batchProcessing => 'Verwerken...';

  @override
  String get batchResults => 'Resultaten';

  @override
  String get batchVerified => 'Geverifieerd';

  @override
  String get batchSealed => 'Verzegeld';

  @override
  String get batchFailed => 'Mislukt';

  @override
  String get batchTotalTime => 'Totale Tijd';

  @override
  String get classificationTitle => 'Classificatie';

  @override
  String get classificationFileLabel => 'Geclassificeerd Bestand';

  @override
  String get classificationCurrentLabel => 'Huidig niveau:';

  @override
  String get classificationNone => 'Geen classificatie ingesteld';

  @override
  String get classificationSetLabel => 'Classificatie Instellen';

  @override
  String get classificationSetAction => 'Classificatie Instellen';

  @override
  String get classificationLevelLabel => 'Classificatieniveau';

  @override
  String get classificationAuthorityLabel => 'Autoriteit';

  @override
  String get classificationAuthorityHint => 'bijv. Beveiligingsfunctionaris';

  @override
  String get classificationCaveatLabel => 'Voorbehoud';

  @override
  String get classificationCaveatHint => 'bijv. NOFORN, ALLEEN VOOR EIGEN OGEN';

  @override
  String get classificationDeclassifyLabel => 'Declassificeren';

  @override
  String get classificationNewLevelLabel => 'Nieuw Niveau';

  @override
  String get classificationDeclassifyAction => 'Declassificeren';

  @override
  String get classificationDeclassifyAuthorityHint => 'bijv. Declassificatie-autoriteit';

  @override
  String get classificationDeclassifyWarningTitle => 'Declassificatie Bevestigen';

  @override
  String get classificationDeclassifyWarningBody => 'Declassificatie verlaagt het beveiligingsniveau van dit document. Deze actie wordt vastgelegd in het auditspoor en kan niet ongedaan worden gemaakt. Doorgaan?';

  @override
  String get classificationPublic => 'OPENBAAR';

  @override
  String get classificationInternal => 'INTERN';

  @override
  String get classificationConfidential => 'VERTROUWELIJK';

  @override
  String get classificationSecret => 'GEHEIM';

  @override
  String get classificationTopSecret => 'ZEER GEHEIM';

  @override
  String get manifestTitle => 'Manifesten';

  @override
  String get manifestCreateTab => 'Aanmaken';

  @override
  String get manifestVerifyTab => 'Verifi\u00ebren';

  @override
  String get manifestFilesLabel => 'Bestanden in Manifest';

  @override
  String get manifestAddFile => 'Bestand Toevoegen';

  @override
  String get manifestNoFiles => 'Geen bestanden toegevoegd. Tik op + om bestanden toe te voegen.';

  @override
  String get manifestSignerIdLabel => 'Ondertekenaar-ID';

  @override
  String get manifestSignerIdHint => 'bijv. auditor@voorbeeld.nl';

  @override
  String get manifestCreateAction => 'Manifest Aanmaken';

  @override
  String get manifestCreating => 'Aanmaken...';

  @override
  String get manifestFileLabel => 'Manifestbestand';

  @override
  String get manifestFileDirectoryLabel => 'Bestandsmap (optioneel)';

  @override
  String get manifestFileDirectoryHint => 'Map met de manifestbestanden voor verificatie';

  @override
  String get manifestVerifyAction => 'Manifest Verifi\u00ebren';

  @override
  String get manifestVerifying => 'Verifi\u00ebren...';

  @override
  String get manifestResultsLabel => 'Verificatieresultaten';

  @override
  String get excerptTitle => 'Uittreksel Bewijs';

  @override
  String get excerptGenerateTab => 'Genereren';

  @override
  String get excerptVerifyTab => 'Verifi\u00ebren';

  @override
  String get excerptFileLabel => 'Bronbestand (.zgl)';

  @override
  String get excerptLoadBlocks => 'Blokken Laden';

  @override
  String get excerptSelectBlocks => 'Blokken Selecteren';

  @override
  String get excerptGenerateAction => 'Bewijs Genereren';

  @override
  String get excerptGenerating => 'Genereren...';

  @override
  String get excerptZglFileLabel => 'Zegel Bestand (.zgl)';

  @override
  String get excerptProofFileLabel => 'Bewijsbestand (.json)';

  @override
  String get excerptVerifyAction => 'Bewijs Verifi\u00ebren';

  @override
  String get excerptVerifying => 'Verifi\u00ebren...';

  @override
  String get excerptProofValid => 'Uittreksel bewijs is GELDIG';

  @override
  String get excerptProofInvalid => 'Uittreksel bewijs is ONGELDIG';

  @override
  String get provenanceTitle => 'Herkomst';

  @override
  String get provenanceFileLabel => 'Te Inspecteren Bestand';

  @override
  String get provenanceLoadAction => 'Herkomst Laden';

  @override
  String get provenanceLoading => 'Laden...';

  @override
  String get provenanceTimeline => 'Herkomsttijdlijn';

  @override
  String get provenanceNoEvents => 'Geen herkomstgebeurtenissen gevonden.';

  @override
  String get provenanceExportReport => 'Rapport Exporteren';

  @override
  String get credentialTitle => 'Certificaten';

  @override
  String get credentialIssueTab => 'Uitgeven';

  @override
  String get credentialVerifyTab => 'Verifi\u00ebren';

  @override
  String get credentialDocumentLabel => 'Certificaatdocument';

  @override
  String get credentialInstitutionLabel => 'Instellingsgegevens';

  @override
  String get credentialInstitutionNameLabel => 'Naam Instelling';

  @override
  String get credentialInstitutionNameHint => 'bijv. Universiteit van Amsterdam';

  @override
  String get credentialInstitutionIdLabel => 'Instelling-ID';

  @override
  String get credentialInstitutionIdHint => 'bijv. NL-UVA-001';

  @override
  String get credentialTypeLabel => 'Type Certificaat';

  @override
  String get credentialTypeDiploma => 'Diploma';

  @override
  String get credentialTypeCertificate => 'Certificaat';

  @override
  String get credentialTypeLicense => 'Licentie';

  @override
  String get credentialTypeAccreditation => 'Accreditatie';

  @override
  String get credentialRecipientLabel => 'Ontvanger';

  @override
  String get credentialRecipientNameLabel => 'Naam Ontvanger';

  @override
  String get credentialRecipientNameHint => 'bijv. Jan de Vries';

  @override
  String get credentialRecipientIdLabel => 'Ontvanger-ID';

  @override
  String get credentialRecipientIdHint => 'bijv. studentnummer of nationaal ID';

  @override
  String get credentialIssueAction => 'Certificaat Uitgeven';

  @override
  String get credentialIssuing => 'Uitgeven...';

  @override
  String get credentialFileLabel => 'Certificaatbestand (.zgl)';

  @override
  String get credentialVerifyAction => 'Certificaat Verifi\u00ebren';

  @override
  String get credentialVerifying => 'Verifi\u00ebren...';

  @override
  String get credentialDetailsLabel => 'Certificaatgegevens';

  @override
  String get credentialIssuedAtLabel => 'Uitgegeven Op';

  @override
  String get credentialValidStatus => 'Certificaat is GELDIG - alle attestaties geverifieerd';

  @override
  String get credentialInvalidStatus => 'Certificaat is ONGELDIG - attestatieverificatie mislukt';

  @override
  String get contractTitle => 'Contract Workflow';

  @override
  String get contractDocumentLabel => 'Contractdocument';

  @override
  String get contractOwnerKeyLabel => 'Eigenaarsleutel';

  @override
  String get contractPartiesLabel => 'Contractpartijen';

  @override
  String get contractNoParties => 'Geen partijen toegevoegd. Tik op de + knop om partijen toe te voegen.';

  @override
  String get contractAddParty => 'Partij Toevoegen';

  @override
  String get contractAddPartyAction => 'Toevoegen';

  @override
  String get contractPartyName => 'Naam Partij';

  @override
  String get contractPartyNameHint => 'bijv. Jan Jansen';

  @override
  String get contractPartyRole => 'Rol';

  @override
  String get contractPartyKey => 'Partij Sleutel (hex)';

  @override
  String get contractPartyKeyHint => '64-teken hex sleutel (optioneel)';

  @override
  String get contractSplitKeyLabel => 'Sleutel Splitsen Configuratie';

  @override
  String get contractEnableSplitKey => 'Multi-Partij Sleutel Splitsen Inschakelen';

  @override
  String get contractWorkflowLabel => 'Werkstroomstappen';

  @override
  String get contractSealAction => 'Contract Verzegelen';

  @override
  String get contractVerifyAttestations => 'Attestaties Verifi\u00ebren';

  @override
  String get settingsDefaultClassification => 'Standaard Classificatieniveau';

  @override
  String get settingsTsaUrl => 'Tijdstempelautoriteit (TSA) URL';

  @override
  String get settingsTsaUrlHint => 'bijv. https://tsa.voorbeeld.nl/tijdstempel';

  @override
  String get settingsAdvancedOptions => 'Geavanceerde Opties';

  @override
  String get settingsPreserveMediaMetadata => 'Media-metadata Behouden';

  @override
  String get settingsPreserveMediaMetadataDesc => 'EXIF, XMP en andere media-metadata behouden bij verzegeling';

  @override
  String get settingsAnonymousMode => 'Anonieme Modus';

  @override
  String get settingsAnonymousModeDesc => 'Gebruikersidentiteit weglaten uit auditspoor en herkomstgegevens';

  @override
  String get sealAnonymousMode => 'Anonieme Modus';

  @override
  String get sealAnonymousModeDesc => 'Identiteit weglaten uit auditspoor';

  @override
  String get sealClassificationLevel => 'Classificatieniveau';

  @override
  String get sealClassificationAuthority => 'Classificatie-autoriteit';

  @override
  String get sealClassificationAuthorityHint => 'bijv. Beveiligingsfunctionaris';

  @override
  String get sealRegulatoryHold => 'Wettelijke Bewaarplicht Datum';

  @override
  String get sealNotSet => 'Niet ingesteld';

  @override
  String get sealTsaUrl => 'TSA URL';

  @override
  String get sealTsaUrlHint => 'Tijdstempelautoriteit URL voor betrouwbare tijdstempels';

  @override
  String get sealPreserveMediaMetadata => 'Media-metadata Behouden';

  @override
  String get sealPreserveMediaMetadataDesc => 'EXIF/XMP-gegevens behouden in verzegeld bestand';

  @override
  String get verifyClassificationLabel => 'Classificatie';

  @override
  String verifyRegulatoryHold(String date) => 'BEWAARD TOT $date';

  @override
  String get verifyTimestampAuthority => 'Tijdstempelautoriteit:';

  @override
  String get verifyAttestationPolicy => 'Attestatiebeleid';

  @override
  String get verifyAllAttestationsValid => 'Alle attestaties geverifieerd';

  @override
  String get verifySomeAttestationsInvalid => 'Sommige attestaties niet geverifieerd';

  @override
  String get verifyProvenancePreview => 'Herkomsttijdlijn';

  @override
  String get helpBatchVerify => 'Alle .zgl bestanden in een map tegelijk verifi\u00ebren';

  @override
  String get helpBatchSeal => 'Alle bestanden in een map verzegelen naar .zgl formaat';

  @override
  String get helpClassification => 'Het beveiligingsniveau van een verzegeld bestand instellen of wijzigen';

  @override
  String get helpManifest => 'Een ondertekende lijst van verzegelde bestanden aanmaken of verifi\u00ebren';

  @override
  String get helpExcerpt => 'Cryptografische bewijzen voor specifieke blokken genereren of verifi\u00ebren';

  @override
  String get helpProvenance => 'De bewakingsketen en herkomstgebeurtenissen bekijken';

  @override
  String get helpCredential => 'Academische certificaten en accreditaties uitgeven of verifi\u00ebren';

  @override
  String get helpContract => 'Multi-partij contract workflow met attestaties en gesplitste sleutels';

  @override
  String get inspectTitle => 'Inspecteren';

  @override
  String get inspectFileLabel => 'Te Inspecteren Bestand';

  @override
  String get helpInspect => 'Bestandsheaderinformatie bekijken zonder de hoofdsleutel';

  @override
  String get mediaMetadataTitle => 'Media-metadata';

  @override
  String get mediaMetadataFileLabel => 'Mediabestand (.zgl)';

  @override
  String get mediaMetadataLoadAction => 'Metadata Laden';

  @override
  String get helpMediaMetadata => 'EXIF, GPS en andere media-metadata van verzegelde bestanden bekijken';

  @override
  String get timestampTitle => 'Tijdstempels';

  @override
  String get timestampCreateTab => 'Aanmaken';

  @override
  String get timestampVerifyTab => 'Verifi\u00ebren';

  @override
  String get timestampFileLabel => 'Te Tijdstempelen Bestand';

  @override
  String get timestampCreateAction => 'Tijdstempel Aanmaken';

  @override
  String get timestampVerifyAction => 'Tijdstempel Verifi\u00ebren';

  @override
  String get helpTimestamp => 'Betrouwbare tijdstempels aanvragen of verifi\u00ebren van een TSA';

  @override
  String get versionChainTitle => 'Versieketen';

  @override
  String get versionChainFileLabel => 'Versiebestanden';

  @override
  String get versionChainAddFile => 'Bestand Toevoegen';

  @override
  String get versionChainVerifyAction => 'Versieketen Verifi\u00ebren';

  @override
  String get versionChainValid => 'Versieketen GELDIG';

  @override
  String get versionChainInvalid => 'Versieketen GEBROKEN';

  @override
  String get helpVersionChain => 'Versiegeschiedenis en ketenhashs bekijken en verifi\u00ebren';

  @override
  String get drawerToolsSection => 'Hulpmiddelen';
}
