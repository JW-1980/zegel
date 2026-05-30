# Software Improvements

## 1. 100 Items to Improve the Software

### UI Improvements
1. Implement a system-wide high-contrast accessibility mode.
2. Add custom scrollbars matching the Zegel brand colors across all website views.
3. Implement a grid layout view option for the user dashboard file list.
4. Standardize empty state illustrations across all lists in both app and website.
5. Add smooth transition animations when switching between dark and light modes.
6. Introduce sticky table headers for long lists on the admin dashboard.
7. Redesign the file upload progress bar to include a percentage and visual byte counter.
8. Implement an interactive collapsible sidebar for the main website navigation.
9. Standardize padding and margin utilities using a strict 8px grid system.
10. Add tooltips to all icon-only buttons for better context.
11. Refine form field focus states with a subtle glow effect.
12. Replace default browser alert dialogs with custom modal components.
13. Add skeleton loading screens for all data-fetching operations.
14. Implement responsive typography that scales fluidly based on screen size.
15. Unify badge designs for file classification levels (e.g., color-coded pills).

### Easier to Use
16. Add a persistent 'Copy to Clipboard' button for all generated hashes and keys.
17. Implement a 'drag-and-drop' zone for the entire screen on the seal view.
18. Add keyboard shortcuts (e.g., Ctrl+S to seal, Ctrl+F to search) on the website.
19. Provide a step-by-step interactive onboarding tour for new signups.
20. Auto-focus the primary input field when any form or modal opens.
21. Allow users to batch-download verified files as a single ZIP archive.
22. Implement a 'Recent Files' quick-access widget on the dashboard.
23. Add contextual help popovers explaining cryptographic terms like 'Merkle Root'.
24. Support deep linking in the Flutter app to directly open specific files from a URL.
25. Add a 'Show Password/Key' toggle icon on all sensitive input fields.
26. Auto-format inputted keys by stripping accidental whitespaces.
27. Allow sorting file lists by clicking on table column headers.

### Additional Automation
28. Automatically compress user-uploaded avatars before saving to storage.
29. Auto-delete expired selective disclosure tokens via a scheduled cron job.
30. Automate weekly database backups and upload them to a secure cold storage.
31. Automatically extract standard file metadata (size, MIME type) upon selection.
32. Implement webhooks to automatically notify external systems of file status changes.
33. Auto-logout users after a configurable period of inactivity for security.
34. Automatically generate a daily summary email of administrative audit logs.
35. Auto-renew SSL certificates via an integrated background job.

### Better User Experience
36. Display estimated time remaining for sealing or verifying exceptionally large files.
37. Provide an offline mode in the Flutter app to view cached manifests.
38. Add an 'Undo' toast notification temporarily allowing reversal of file deletions.
39. Save and persist the user's preferred pagination size across sessions.
40. Implement infinite scrolling on the audit log view.
41. Localize all timestamps to the user's detected browser timezone.
42. Provide a visual diff tool to compare metadata changes between file versions.
43. Add a 'Back to Top' floating action button on long list views.
44. Highlight newly added items in lists with a temporary background fade.

### Improved Security
45. Enforce mandatory TOTP Two-Factor Authentication for all admin roles.
46. Implement strict rate limiting on all authentication and API endpoints.
47. Add robust Content Security Policy (CSP) headers to the Laravel application.
48. Automatically temporarily ban IP addresses after multiple failed login attempts.
49. Require password re-entry before performing destructive actions like deleting keys.
50. Invalidate all other active sessions when a user changes their password.
51. Check passwords against a breached password dictionary during registration.
52. Implement Subresource Integrity (SRI) tags for all loaded external scripts.
53. Obfuscate internal database IDs by using UUIDs in all public-facing URLs.
54. Add a 'Security Audit Log' tab in user settings showing login IPs and devices.

### Improved Performance
55. Implement Redis caching for frequently accessed configuration and taxonomy data.
56. Enable GZIP/Brotli compression explicitly on the web server layer.
57. Lazy load all images and off-screen components on the website.
58. Add optimal database indexes to frequently searched columns like file hashes.
59. Defer non-essential initializations in the Flutter app to speed up startup time.
60. Offload client-side cryptographic hashing to Web Workers to prevent UI freezing.
61. Utilize cursor-based pagination for large database tables instead of offset pagination.
62. Bundle and minify all CSS/JS assets aggressively using a modern build tool.

### Data Leakage Prevention & Privacy
63. Sanitize all uploaded file names to remove potential PII before server storage.
64. Implement a comprehensive 'Download My Data' export feature for GDPR compliance.
65. Create a 'Hard Delete' function that completely overwrites and scrubs user data.
66. Strip EXIF and hidden metadata from uploaded media and avatars.
67. Mask the final octet of IP addresses in application logs for privacy.
68. Ensure all database backups are encrypted at rest using an external KMS.
69. Provide a granular cookie consent manager allowing users to opt-out of trackers.
70. Add strict `Cache-Control: no-store` headers to all pages displaying sensitive data.
71. Redact all potential user input from automated crash reports.

### Telemetry & Statistics Display
72. Create an administrative dashboard chart showing file sealing volume over 30 days.
73. Display a storage quota progress bar in the user account settings.
74. Track and display the average processing time for verifying files per platform.
75. Implement a public 'System Status' page showing API uptime and historical availability.
76. Collect anonymous usage metrics on which CLI commands are invoked most often.
77. Display a pie chart breakdown of file classifications on the admin panel.
78. Create a 'Contribution Heatmap' showing a user's file sealing activity over the year.
79. Show real-time active user session counts in the admin dashboard.
80. Display a simple network latency indicator in the app settings for troubleshooting.

### Better CRUD & Standardization
81. Implement soft deletes universally across all primary Eloquent models.
82. Standardize all API JSON responses to conform strictly to the JSON:API specification.
83. Create a universal generic 'DataTable' Blade component to enforce DRY principles.
84. Mandate the use of Laravel Form Requests for all incoming validation logic.
85. Refactor the Flutter UI to use centralized, reusable custom widget classes (e.g., `ZegelCard`).
86. Add bulk action checkboxes to all list views (e.g., Bulk Delete, Bulk Classify).
87. Standardize error codes across the API and CLI to simplify cross-platform debugging.
88. Add inline editing capabilities for simple text fields within data tables.
89. Implement faceted search sidebars for complex index views.
90. Add an automatic activity log trait tracking `created_by` and `updated_by` for all models.

### User Interaction & Misc
91. Add a private note-taking feature attached to individual file detail pages.
92. Implement a real-time notification bell system for file status alerts.
93. Allow users to 'Star' or 'Pin' important files to the top of their dashboard.
94. Create a shared workspace feature for teams to collaborate on manifests.
95. Implement a 'Share via Secure Link' feature with time expiry and password protection.
96. Add an internal support ticketing module for users to contact administrators.
97. Introduce granular user roles (e.g., View-Only, Sealer, Auditor, Admin).
98. Build a public registry feature allowing users to publish specific verified files.
99. Sync the user's dark/light mode preference across all their authenticated devices.
100. Provide a syntax-highlighting code viewer for inspecting JSON token files directly in the browser.

---

## 2. 15 Items for Easier Installation/Hosting

1. Provide a ready-to-use generalized systemd service file for running the Zegel worker queue.
2. Create a one-click deployment script specifically for DigitalOcean App Platform.
3. Publish an official standalone Snap package for the Linux CLI.
4. Include a comprehensive deployment guide tailored for AWS Elastic Beanstalk.
5. Add a setup wizard CLI command (`php artisan zegel:install`) that validates the environment.
6. Provide pre-configured Nginx and Apache virtual host templates in the repository.
7. Support SQLite out-of-the-box as a zero-configuration default for local development.
8. Implement an automatic database migration check on application boot.
9. Provide an official Nix flake for declarative environment setups.
10. Add a dedicated `/health` HTTP endpoint structured for load balancer probes.
11. Include a robust configuration script to automatically handle directory permissions (`chmod`/`chown`).
12. Create a setup guide for hosting the application using Laravel Forge.
13. Ensure all application logs output cleanly to `stdout`/`stderr` by default for easier log aggregation.
14. Offer a pre-configured generic reverse-proxy setup guide (e.g., Traefik or Caddy).
15. Publish an official Chocolatey package for Windows CLI installation.

---

## 3. Recommended Redesigns

### 20 Flutter App Screens to Redesign
1. **home_screen.dart**: Redesign to act as a comprehensive dashboard rather than a simple menu. Include a quick-access grid for recent files and status widgets.
2. **seal_screen.dart**: Implement a multi-step wizard UI instead of a single long form, making complex options like expiration and classification more digestible.
3. **verify_screen.dart**: Transform the results view into a bold, high-contrast summary screen (prominent green/red indicators) followed by a collapsible technical details section.
4. **keygen_screen.dart**: Add an interactive entropy/strength meter and a clearly visible, one-tap 'Copy to Clipboard' workflow immediately after generation.
5. **settings_screen.dart**: Break the long list of settings into distinct tabbed categories (General, Security, Network, Appearance) for easier navigation.
6. **attest_screen.dart**: Redesign with a visual 'certificate' or 'signature pad' motif to emphasize the gravity and legal nature of adding an attestation.
7. **audit_screen.dart**: Replace the standard list view with a vertical timeline component, grouping events by day to better visualize the history of actions.
8. **batch_screen.dart**: Introduce a detailed overall progress ring, along with individual item status indicators and a clear 'Cancel Batch' button during processing.
9. **canary_screen.dart**: Simplify the interface by visually explaining canary traps through a graphic, paired with a straightforward toggle and recipient input list.
10. **classification_screen.dart**: Utilize distinct, bold color codes and iconography (e.g., bright red for TOP SECRET) to make classification changes unmistakably clear.
11. **contract_screen.dart**: Adopt a split-pane layout for tablets/desktop, showing document details on one side and a grid of involved parties on the other.
12. **credential_screen.dart**: Redesign to visually mimic a digital wallet or ID card, making the academic/institutional credentials feel more authentic and recognizable.
13. **disclose_screen.dart**: Build an interactive block-selection interface that graphically represents the file chunks being included or excluded in the disclosure.
14. **envelope_screen.dart**: Incorporate subtle animations (e.g., an envelope closing or sealing) to provide rewarding visual feedback when a file is successfully wrapped.
15. **excerpt_screen.dart**: Integrate a built-in text or hex viewer allowing users to highlight the exact portion of the file they wish to prove, rather than entering manual block numbers.
16. **extract_screen.dart**: Clean up the UI with a prominent destination folder selector and a dynamic estimated time remaining indicator for large extractions.
17. **inspect_screen.dart**: Swap out raw text dumping for a structured, collapsible property grid or a stylized JSON tree viewer for better readability.
18. **manifest_screen.dart**: Present the manifest contents as an interactive tree view or a clear checklist, showing the hierarchy and status of all linked files.
19. **media_metadata_screen.dart**: Feature image/video thumbnail previews at the top, followed by an organized, sortable table for EXIF and media property data.
20. **provenance_screen.dart**: Replace the linear list with a graphical node-and-edge visualization to effectively map out the complete chain of custody.

### 20 Laravel Website Views to Redesign
1. **welcome.blade.php**: Modernize the landing page with scroll-triggered animations, clear call-to-action buttons, and an illustrative breakdown of the 'Tamper-proof' concept.
2. **user/dashboard.blade.php**: Convert into a modular, widget-based overview that displays key usage statistics, recent activity, and quick-action links.
3. **user/files/index.blade.php**: Upgrade the standard table to a rich data grid featuring sortable columns, inline status badges, and bulk action checkboxes.
4. **user/files/create.blade.php**: Implement a sleek, full-width drag-and-drop 'dropzone' area that immediately provides visual feedback upon file selection.
5. **admin/dashboard.blade.php**: Incorporate dynamic charts (e.g., Chart.js) to visualize system health, user registration trends, and storage quota utilization.
6. **admin/users/index.blade.php**: Add faceted filtering options (by role, status, creation date) and a compact row design to handle larger user bases efficiently.
7. **admin/settings/edit.blade.php**: Organize the exhaustive form into horizontal tabs (General, Security, Mail, Advanced) to prevent overwhelming the administrator.
8. **auth/login.blade.php**: Refine into a centered, card-based design with a modern, subtle background, clear focus states, and space for potential SSO buttons.
9. **auth/register.blade.php**: Enhance the form with a real-time password strength meter and immediate inline validation feedback for all fields.
10. **auth/forgot-password.blade.php**: Simplify the messaging for clarity and ensure a prominent, easy-to-find link back to the main login screen.
11. **auth/reset-password.blade.php**: Add dual password input fields with real-time matching validation to prevent typos during the reset process.
12. **installer/welcome.blade.php**: Introduce a step-by-step 'Wizard' progress tracker at the top of the page to orient the user during the installation sequence.
13. **installer/requirements.blade.php**: Utilize distinct green (success) and red (failure) badges for each PHP extension or system requirement for instant scannability.
14. **installer/database.blade.php**: Include a dedicated 'Test Connection' button that provides asynchronous feedback before allowing the user to proceed.
15. **installer/admin.blade.php**: Visually differentiate this crucial step with a distinct header or warning color to emphasize the importance of securing the admin account.
16. **search/index.blade.php**: Implement a robust sidebar containing faceted search filters (e.g., by date range, file type, or classification level) alongside results.
17. **downloads/index.blade.php**: Restructure into a grid of clean download cards, each prominently displaying the version number, release date, and platform icon.
18. **verify/show.blade.php**: Design a high-contrast success/failure banner and provide a visually clear breakdown of the verification math (e.g., Merkle root matching).
19. **legal/privacy.blade.php**: Enhance readability with a structured layout, larger typography, and a sticky table of contents for navigating different legal sections.
20. **user/account/edit.blade.php**: Create dedicated, distinctly styled sections for enabling Two-Factor Authentication and managing active browser sessions.
