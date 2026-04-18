import json

tests = {}
errors = []

with open("lib/test_json.log") as f:
    for line in f:
        try:
            data = json.loads(line)
            if data.get("type") == "testStart":
                tests[data["test"]["id"]] = data["test"]["name"]
            elif data.get("type") == "error":
                test_id = data.get("testID")
                name = tests.get(test_id, "Unknown Test")
                errors.append(name)
        except:
            pass

print(errors)
