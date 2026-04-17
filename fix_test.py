# The tests failed on GitHub Actions but passed locally.
# It seems there's a race condition or time dependency.
# Look at the failed tests from the GHA log:
#   2026-04-17T17:22:40.4812479Z ##[error]1277 tests passed, 9 failed.
# I will parse the GHA log again and find the word "failed" precisely to get the test names.
