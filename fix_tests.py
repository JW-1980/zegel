import os

def fix_test_file(path):
    with open(path, 'r') as f:
        content = f.read()

    # Revert 'const expiration = DateTime' to 'final expiration = DateTime'
    # Actually, earlier I replaced 'final expiration =' with 'const expiration ='. Let's replace 'const expiration = DateTime' with 'final expiration = DateTime'
    # because DateTime cannot be const.
    content = content.replace("const expiration = DateTime", "final expiration = DateTime")
    content = content.replace("const timestamp = DateTime", "final timestamp = DateTime")

    # Let's fix test/writer_test.dart:192 and 207 `const_eval_method_invocation`
    # test/provenance_verification_test.dart:40:23 `const timestamp = DateTime`
    # I did the replacement but maybe there are other variables?

    with open(path, 'w') as f:
        f.write(content)

for root, dirs, files in os.walk('lib/test'):
    for file in files:
        if file.endswith('.dart'):
            fix_test_file(os.path.join(root, file))

print("Fixed tests.")
