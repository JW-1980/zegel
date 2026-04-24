/// Zegel: A tamper-proof container format library.
///
/// Zegel ("seal" in Dutch) wraps any file in a cryptographic container that
/// makes the content physically unreadable if even a single byte is modified
/// after creation. This is not a "check and warn" system -- the cryptographic
/// math itself prevents decoding of tampered content.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:zegel/zegel.dart';
///
/// // Create a sealed container
/// final writer = ZegelWriter(masterKey, ZegelOptions(contentType: 'text/plain'));
/// final sealed = writer.seal(utf8.encode('Hello, Zegel!'));
///
/// // Verify and extract
/// final reader = ZegelReader();
/// final result = reader.verify(sealed, masterKey);
/// assert(result.valid);
/// ```
library zegel;

export 'src/format.dart';
export 'src/merkle_tree.dart';
export 'src/key_derivation.dart';
export 'src/writer.dart';
export 'src/reader.dart';
export 'src/canary.dart';
export 'src/shamir.dart';
export 'src/redaction.dart';
export 'src/attestation.dart';
export 'src/disclosure.dart';
export 'src/audit.dart';
export 'src/versioning.dart';
export 'src/batch.dart';
export 'src/manifest.dart';
export 'src/classification.dart';
export 'src/excerpt.dart';
export 'src/media_metadata.dart';
export 'src/timestamp.dart';
export 'src/roughtime.dart';
export 'src/provenance_verification.dart';
export 'src/hierarchical_split_key.dart';
export 'src/streaming.dart';
export 'src/burn_after_read.dart';
export 'src/time_lock.dart';
export 'src/identity.dart';
export 'src/supply_chain.dart';
export 'src/structured_blocks.dart';
export 'src/wet_signature.dart';
export 'src/envelope.dart';
export 'src/template.dart';
export 'src/certificate_of_completion.dart';
export 'src/bulk_send.dart';
// v1.3 operational improvements
export 'src/preferences.dart';
export 'src/sealing_template.dart';
export 'src/token_archive.dart';
export 'src/webhook.dart';
export 'src/cron_template.dart';
export 'src/key_rotation_reminder.dart';
export 'src/usage_analytics.dart';
export 'src/hardware_info.dart';
export 'src/failure_stats.dart';
export 'src/latency_tracker.dart';
export 'src/feature_ratings.dart';
export 'src/secure_memory.dart';
export 'src/password_strength.dart';
export 'src/verification_cache.dart';
export 'src/pii_detector.dart';
export 'src/retention_policy.dart';
export 'src/history_log.dart';
export 'src/csv_report.dart';
export 'src/time_saved.dart';
export 'src/contact_book.dart';
export 'src/temp_file_cleanup.dart';
export 'src/watch_folder.dart';
// v1.3 operational improvements, batch 2
export 'src/key_backup.dart';
export 'src/report_generator.dart';
export 'src/crash_reporter.dart';
export 'src/anonymizer.dart';
export 'src/undo_manager.dart';
export 'src/batch_controller.dart';
export 'src/session_lockout.dart';
export 'src/isolate_pool.dart';
export 'src/prefetch_queue.dart';
export 'src/safe_view.dart';
export 'src/seal_preflight.dart';
export 'src/secure_delete.dart';
export 'src/metadata_stripper.dart';
export 'src/classification_stats.dart';
export 'src/resource_monitor.dart';
export 'src/key_health_dashboard.dart';
export 'src/collaborator_stats.dart';
export 'src/operation_baseline.dart';
export 'src/eta_calculator.dart';
export 'src/shortcut_registry.dart';
export 'src/search_filter.dart';
export 'src/help_registry.dart';
export 'src/tutorial_sequence.dart';
export 'src/statistics_dashboard.dart';
export 'src/dashboard_catalog.dart';
// v1.3 operational improvements, batch 3
export 'src/theme_scheduler.dart';
export 'src/theme_brand.dart';
export 'src/field_validator.dart';
export 'src/crypto_glossary.dart';
export 'src/clipboard_helper.dart';
export 'src/selection_state.dart';
export 'src/feedback_submitter.dart';
export 'src/offline_indicator.dart';
export 'src/reveal_in_os.dart';
export 'src/accessibility_theme.dart';
export 'src/totp.dart';
export 'src/mmap_reader.dart';
export 'src/key_manager.dart';
export 'src/template_manager.dart';
export 'src/log_view_formatter.dart';
export 'src/web_setup_wizard.dart';
