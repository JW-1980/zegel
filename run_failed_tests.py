import json
import subprocess
import os

failed_tests = []
with open("lib/test_json.log") as f:
    for line in f:
        try:
            data = json.loads(line)
            if data.get("type") == "testDone" and data.get("result") != "success":
                failed_tests.append(data.get("testID"))
        except:
            pass

tests_info = {}
with open("lib/test_json.log") as f:
    for line in f:
        try:
            data = json.loads(line)
            if data.get("type") == "testStart":
                tests_info[data["test"]["id"]] = {
                    "name": data["test"]["name"],
                    "url": data["test"].get("url")
                }
        except:
            pass

failed_files = set()
for tid in failed_tests:
    info = tests_info.get(tid)
    if info and info.get("url"):
        url = info["url"]
        if url.startswith("file://"):
            url = url[len("file://"):]
        failed_files.add(url)

print("Failed files:", failed_files)
