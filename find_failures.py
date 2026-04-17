with open("lib/test_output.log", "r") as f:
    for line in f:
        if "FAILED" in line or "failed" in line or "-1" in line:
            print(line.strip())
