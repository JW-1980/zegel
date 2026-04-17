import glob
import os
import re

# Some files had SecureMemory.wipe(masterKey); added where masterKey was not defined.
# I reverted them. Let's ONLY add it where masterKey is defined.

for fpath in glob.glob("cli/lib/commands/*.dart"):
    with open(fpath, "r") as f:
        content = f.read()

    if "SecureMemory.wipe(masterKey);" not in content:
        if "masterKey = parseKeyFromArgs" in content or "Uint8List masterKey;" in content:
            # It's defined, so let's carefully place the wipe before return.
            # But the simplest is just relying on the ones already patched. Let's see what is already patched.
            pass
