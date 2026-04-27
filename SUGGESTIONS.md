# Software Suggestions

## 100 Improvements

### Better looking / UI improvements
1. Add subtle drop shadows to card components for depth.
2. Ensure minimum touch targets of 48x48dp for all interactive elements in the Flutter app.
3. Implement smooth color transitions when toggling between light and dark modes.
4. Introduce a custom icon set specifically designed for cryptographic concepts.
5. Provide a compact view mode for the dashboard to show more items without scrolling.
6. Use glassmorphism effects for floating action buttons.
7. Add a progress bar that runs across the top edge of the screen during page loads.
8. Support animated splash screens during app startup.
9. Implement a visual "confetti" or success animation after a successful document seal.
10. Adopt a standardized color scale with 10 shades for each primary color.
11. Implement sticky sidebars on wide screens for persistent navigation.
12. Use inline validation with subtle icon changes (red cross to green check) inside text fields.
13. Replace standard modals with bottom sheets on mobile devices.
14. Animate the expansion and collapse of accordion sections.
15. Add subtle hover effects to table rows in the admin view.

### Easier to use
16. Implement a "Save as Template" feature for frequently used metadata configurations.
17. Add an "Undo" snackbar after deleting files or records.
18. Support drag-and-drop file reordering in batch operations.
19. Enable copying of complex IDs (like Merkle roots) with a single click button next to them.
20. Add keyboard navigation for all data tables (up/down arrows).
21. Implement a unified search bar that searches both files and settings.
22. Provide a "Clear all filters" button when multiple search filters are active.
23. Add a "Show Password" toggle button on login and registration forms.
24. Allow users to rename uploaded files directly in the list view by double-clicking.
25. Auto-focus the primary input field when a new modal or screen opens.
26. Support pasting images directly from the clipboard to attach them.
27. Allow batch downloading of selected files as a zip archive.

### Additional automation
28. Support automatic archiving of files after a user-defined period.
29. Add scheduled webhook triggers based on time, not just events.
30. Automatically generate weekly summary reports of sealed files for admins.
31. Support automatic rotation of API keys with grace periods.
32. Automatically retry failed external API calls with exponential backoff.
33. Add an auto-logout feature based on inactivity.
34. Automatically compress image attachments before sealing them.

### Free ways of gathering more useful and relevant data
35. Implement a feedback button allowing users to submit bug reports directly from the app.
36. Add optional exit surveys when a user deletes their account.
37. Track the most frequently used search terms to improve the search algorithm.
38. Monitor which help documentation links are clicked most often.
39. Record the typical file sizes being sealed to optimize storage configurations.
40. Log the average time users spend on the verification screen to identify bottlenecks.
41. Gather metrics on which authentication methods are most popular.

### Better user experience
42. Provide offline mode support in the Flutter app for viewing previously verified seals.
43. Add a "Read time" estimate to long documentation pages.
44. Show detailed error messages with error codes that can be easily searched.
45. Implement "Smart defaults" for form fields based on the user's previous inputs.
46. Create a quick "Getting Started" checklist for new users.
47. Support multi-window or tabbed views within the desktop Flutter app.
48. Add a "Night Mode" that heavily reduces blue light emissions.
49. Ensure all form submissions have a visible loading state to prevent double-clicks.

### Improved security
50. Implement Content Security Policy (CSP) headers across all web pages.
51. Add support for FIDO2 / WebAuthn hardware security keys.
52. Support IP-based allowlisting for administrative access.
53. Automatically block IP addresses after 10 failed login attempts.
54. Require re-authentication for sensitive actions like deleting an account.
55. Display the date and location of the last successful login on the dashboard.
56. Enforce a minimum password length of 12 characters and check against breached password databases.
57. Implement Rate Limiting specifically for the password reset endpoint.

### Improved performance
58. Utilize Web Workers for heavy cryptographic operations in the browser to prevent UI blocking.
59. Implement virtual scrolling for data tables with thousands of rows.
60. Preload critical web fonts using `<link rel="preload">`.
61. Lazy load images below the fold in documentation and landing pages.
62. Use Flutter's `RepaintBoundary` to optimize animations and reduce unnecessary widget rebuilds.
63. Cache the results of complex database queries using Redis.
64. Minify and bundle all CSS and JS assets (if not fully optimized yet).

### Improved PII and other data leakage prevention or handling
65. Add a data scrubbing feature that automatically detects and masks credit card numbers in text fields.
66. Implement an automatic expiration feature for temporary share links.
67. Ensure all sensitive user logs are automatically purged after 90 days.
68. Mask email addresses in public-facing search results (e.g., j***@example.com).
69. Add a "Data Subject Access Request" form directly in the privacy policy page.
70. Ensure API responses strip out all internal database IDs and only return public UUIDs.
71. Add an option to "Erase my activity data" without deleting the main account.

### Telemetry collection
72. Implement distributed tracing using OpenTelemetry.
73. Collect anonymized crash reports from the Flutter app using Sentry.
74. Track frontend JavaScript errors and log them to a central server.
75. Monitor database query execution times and flag queries slower than 100ms.
76. Record the success rate of webhook deliveries.

### Display of interesting or useful statistics
77. Show users a graph of their activity over the last 30 days.
78. Display the global number of active nodes or users currently online.
79. Show a leaderboard of the most active public contributors (if applicable).
80. Display the total disk space saved by using optimized compression.
81. Show the uptime percentage of the service on the public landing page.

### CRUD where possible
82. Add CRUD operations for user-defined tags.
83. Implement CRUD functionality for saved search filters.
84. Add CRUD management for organizational teams or groups.
85. Allow CRUD operations for custom webhook payloads.
86. Add CRUD functionality for personal notification preferences.

### Creating standardized components according to SOLID and DRY principle
87. Create a generic "List/Detail" layout component that can be reused for any entity.
88. Extract date-formatting logic into a centralized utility service.
89. Build a standardized "Empty State" component for all lists.
90. Abstract the API client logic to automatically handle token refreshing and retries.
91. Create a reusable pagination control component.

### Features that encourage interaction
92. Implement a simple "Upvote" or "Star" system for public files.
93. Add a built-in messaging system for users within the same organization.
94. Create a public forum or discussion board for users to ask questions.
95. Allow users to follow specific public files and receive notifications on updates.
96. Implement user profiles with public bios and links.

### Anything else
97. Add support for exporting reports directly to Google Sheets.
98. Provide a "Sandbox Environment" for developers to test API integrations.
99. Add support for creating RSS feeds of public file updates.
100. Implement a feature to embed public files in external websites using an iframe.

## 15 Items for Easier Installation/Hosting
1. Create a Nix flake for reproducible development and deployment environments.
2. Provide a one-click deployment template for DigitalOcean App Platform.
3. Publish a comprehensive Helm chart for deploying to Kubernetes clusters.
4. Supply a pre-configured Vagrantfile for local virtual machine setups.
5. Create a setup wizard script that automatically generates `.env` files based on user prompts.
6. Provide an official AWS CloudFormation template.
7. Offer a pre-built Docker Compose profile specifically for "production-lite" setups.
8. Create a script to easily migrate data from SQLite to PostgreSQL.
9. Publish a guide for deploying the application on a homelab using Proxmox.
10. Add support for deploying the static website via GitHub Pages.
11. Provide a template for deploying with Railway.app.
12. Create a comprehensive guide for setting up automated Let's Encrypt SSL certificates.
13. Publish a pre-configured configuration for deploying on Vultr.
14. Offer an automated backup script that saves database dumps to an S3-compatible bucket.
15. Create a `brew tap` for easy installation of the CLI tool on macOS.

## 20 Screens of Flutter App to Redesign
1. `app/lib/screens/home_screen.dart`: Needs a more intuitive dashboard layout focusing on primary user actions instead of just listing stats.
2. `app/lib/screens/settings_screen.dart`: Should be reorganized into tabs or sub-pages, as it's currently too cluttered and hard to navigate on small screens.
3. `app/lib/screens/verify_screen.dart`: The success/failure states need stronger visual differentiation; currently, it relies too heavily on text.
4. `app/lib/screens/audit_screen.dart`: Needs a visual timeline component instead of a plain list to better represent sequential events.
5. `app/lib/screens/keygen_screen.dart`: The entropy gathering process should have a more engaging, gamified UI to encourage better user participation.
6. `app/lib/screens/attest_screen.dart`: The signature confirmation step is visually weak and needs a more prominent, distinct confirmation dialog.
7. `app/lib/screens/batch_screen.dart`: Needs better visual feedback for the progress of individual files within a batch, such as individual progress bars.
8. `app/lib/screens/canary_screen.dart`: The display of canary status is confusing; it should use clear "healthy/triggered" visual indicators.
9. `app/lib/screens/classification_screen.dart`: Needs color-coded badges or distinct visual hierarchy to differentiate security levels at a glance.
10. `app/lib/screens/contract_screen.dart`: The document comparison view is cramped; it needs a side-by-side or overlay view for better readability.
11. `app/lib/screens/credential_screen.dart`: Should visually resemble a digital wallet or ID card to mentally map to physical credentials.
12. `app/lib/screens/disclose_screen.dart`: The UI for selecting what to disclose is clunky; a visual document preview with selectable regions would be better.
13. `app/lib/screens/envelope_screen.dart`: Lacks visual metaphor; adding animations of an envelope opening/closing would improve the experience.
14. `app/lib/screens/excerpt_screen.dart`: Selecting parts of a tree is abstract; a visual node-graph selector would make the process much clearer.
15. `app/lib/screens/extract_screen.dart`: The extraction progress needs a clearer multi-stage visual indicator (e.g., Decrypting -> Decompressing).
16. `app/lib/screens/inspect_screen.dart`: The raw data view is overwhelming; it should use an expandable tree view for structured data.
17. `app/lib/screens/manifest_screen.dart`: Complex manifests are hard to read; they need a collapsible, hierarchical view.
18. `app/lib/screens/media_metadata_screen.dart`: Media previews are too small; it needs a dedicated media viewer with an overlay for metadata.
19. `app/lib/screens/provenance_screen.dart`: Chain of custody should be visualized as an interactive flowchart, not just text.
20. `app/lib/screens/redact_screen.dart`: The redaction tools are hard to use on mobile; needs a zoomable canvas with precise touch controls.

## 20 Pages of Laravel Website to Redesign
1. `website/resources/views/welcome.blade.php`: The landing page lacks a clear, prominent call-to-action and could benefit from an interactive demo.
2. `website/resources/views/home.blade.php`: The user dashboard needs a customized layout focusing on recent activity rather than static information.
3. `website/resources/views/auth/login.blade.php`: Needs a more modern, centered card layout and options for social login if applicable.
4. `website/resources/views/auth/register.blade.php`: The form is too long; breaking it into a multi-step process would improve conversion.
5. `website/resources/views/files/show.blade.php`: The file details are poorly organized; cryptographic proofs should be highlighted in a dedicated side panel.
6. `website/resources/views/admin/dashboard.blade.php`: Admin metrics are cluttered; needs a customizable widget-based layout.
7. `website/resources/views/admin/users/index.blade.php`: The user list lacks advanced filtering and bulk action capabilities.
8. `website/resources/views/admin/audit/index.blade.php`: Audit logs are hard to parse; needs a clear timeline view and better filtering by event type.
9. `website/resources/views/admin/settings/index.blade.php`: Settings are lumped together; needs categorization with tabs for easier navigation.
10. `website/resources/views/user/profile.blade.php`: The profile page is scattered; needs a unified tabbed interface for account details and security.
11. `website/resources/views/downloads/index.blade.php`: The download history is a plain table; a grid view with file icons would be more user-friendly.
12. `website/resources/views/search/index.blade.php`: Search results are plain; adding rich snippets and highlighting match terms would improve usability.
13. `website/resources/views/installer/index.blade.php`: The installation wizard steps are unclear; needs better progress tracking and inline validation.
14. `website/resources/views/legal/terms.blade.php`: A wall of text; needs a sticky table of contents and collapsible sections.
15. `website/resources/views/legal/privacy.blade.php`: Needs a summary sidebar highlighting key points for quick reading.
16. `website/resources/views/verify/index.blade.php`: The verification form is too small; dragging and dropping files should be the primary, full-screen action.
17. `website/resources/views/partials/navbar.blade.php`: Navigation becomes cluttered on mobile; needs a cleaner off-canvas hamburger menu.
18. `website/resources/views/partials/footer.blade.php`: The footer is disproportionately large; links should be condensed into a cleaner grid.
19. `website/resources/views/errors/404.blade.php`: The error page is generic; needs custom illustrations and helpful links back to main content.
20. `website/resources/views/errors/500.blade.php`: Needs a more reassuring message and an option to report the issue directly.
