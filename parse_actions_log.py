import re

log_file = "lib/test_output.log"

with open(log_file, "r") as f:
    for line in f:
        if line.startswith("00:") and " [E]" in line:
            print(line)
