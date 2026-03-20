import re

with open('lib/lib/src/reader.dart', 'r') as f:
    content = f.read()

# If `disclosedIndices` is undefined, we probably removed its initialization completely or put it in the wrong scope.
# Let's restore the original file from git and just leave the warning if it's unused, or fix it properly.
