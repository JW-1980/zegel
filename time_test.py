# The only tests that fail in GitHub Actions are related to something that is unstable.
# One possibility is `Future.delayed(const Duration(...))`
# Let's globally replace them with explicit `<void>`
import glob

for fpath in glob.glob("lib/test/*.dart"):
    with open(fpath, "r") as f:
        content = f.read()

    if "Future.delayed(const Duration" in content:
        content = content.replace("Future.delayed(const Duration", "Future<void>.delayed(const Duration")
        with open(fpath, "w") as f:
            f.write(content)
