1. **Understand Memory constraints:**
   - Normalizing input paths to absolute paths (`File(path).absolute.path`).
   - Rejecting URI schemes/URLs (`path.contains('://')`).
   - Internally quoting Windows `explorer` arguments (e.g., `/select,"$path"`).
   - Using the `--` argument separator for macOS `open` and Linux `xdg-open`.
   - In tests, mock OS-specific absolute paths dynamically using `File(path).absolute.path` to avoid failures on different host OSes.

2. **Modify `lib/lib/src/reveal_in_os.dart`**:
   - Add the URI check (`if (path.contains('://')) throw ArgumentError(...);`).
   - Use `File(path).absolute.path` to normalize.
   - Update Windows args: `['/select,"$normalizedPath"']`.
   - Update macOS args: `['-R', '--', normalizedPath]`.
   - Update Linux args: `['--', _parentOf(normalizedPath)]`.

3. **Update `lib/test/reveal_in_os_test.dart`**:
   - Update the expected arguments with dynamically resolved absolute paths (`File(path).absolute.path`).
   - Add new tests for URL rejection.
   - Update `--` argument validations for macOS and Linux.

4. **Complete pre-commit steps to ensure proper testing, verification, review, and reflection are done.**

5. **Submit changes**
