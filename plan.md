1. **Analyze the failures**:
   - The `App Tests` job fails at `flutter analyze`. Actually no, `flutter analyze` runs without issues. It fails at `dart format --output=none --set-exit-if-changed .` in the `app` directory.
   - The files failing format in `app` are: `audit_screen.dart`, `batch_screen.dart`, `canary_screen.dart`, `classification_screen.dart`, `contract_screen.dart`, `credential_screen.dart`, `disclose_screen.dart`, `envelope_screen.dart`, `excerpt_screen.dart`, `inspect_screen.dart`, `keygen_screen.dart`, `redact_screen.dart`, `seal_screen.dart`, `verify_screen.dart`, `version_chain_screen.dart`, `wet_signature_screen.dart`, `contact_service.dart`, `error_helper.dart`, `key_service.dart`, `zegel_service.dart`, `attestation_badge.dart`, `inactivity_lock.dart`, `key_input.dart`, `sensitive_field.dart`.
   - The `Library Tests` job fails at `dart format --output=none --set-exit-if-changed .` in the `lib` directory.
   - The files failing format in `lib` are: `bulk_send.dart`, `certificate_of_completion.dart`, `envelope.dart`, `field_validator.dart`, `help_registry.dart`, `shortcut_registry.dart`, `template.dart`, `time_saved.dart`, `tutorial_sequence.dart`.
   - Wait, I literally *just* ran `dart format .` on these files in the previous plan!
   - Why are they STILL failing formatting checks in CI?
   - Oh! I changed them, committed them, and pushed them. But I used `dart format` from Dart SDK 3.11.0 locally. The CI is running Dart SDK 3.11.4 or Flutter SDK 3.41.6. They might have different formatting rules.
   - Let's check the CI logs again for `Library Tests`:
     - Installing the linux-x64 Dart SDK version 3.11.4
     - It formats `bulk_send.dart`, `certificate_of_completion.dart`... Wait, I used `dart fix --apply` and it moved constructors! Moving constructors changes the code. Maybe after `dart fix --apply` moved the constructors, the file became unformatted again, and I didn't re-run `dart format .` after `dart fix --apply`! Let's check my previous plan. I ran `dart format .`, then `dart fix --apply`. Yes, `dart fix --apply` changed the files, but I forgot to run `dart format .` AFTER `dart fix --apply`! This explains `lib`.
   - What about `app`? I ran `dart format .` in `app` in the first step. Then I never touched `app` again. Why is `app` failing `dart format .` in CI?
   - Oh, I did NOT commit the `dart format .` changes in `app`! My previous `git diff --staged` only showed `app/lib/gen_l10n/app_localizations.dart` because I manually `git restore --staged` the others, or I didn't `git add` them!
   - Let's check `git show 67439f7`. I only committed `app/lib/gen_l10n/app_localizations.dart`!
   - Ah! The `git commit -m "Fix linting and formatting issues across codebase"` committed 93 files. But wait, `app` files were 24 files! 93 files is exactly the number of files changed by `dart fix` and some formatting. I need to format `app` and add all of it.
2. **Action Plan**:
   - Run `dart format .` in `app`, `cli`, and `lib` to ensure everything is perfectly formatted.
   - Stage everything and commit.
