import sys

def main():
    path = "app/lib/screens/version_chain_screen.dart"
    with open(path, "r") as f:
        content = f.read()

    new_snippet2 = """                        itemCount: _filePaths.length,
                        // ignore: deprecated_member_use
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex--;
                            final item = _filePaths.removeAt(oldIndex);
                            _filePaths.insert(newIndex, item);
                            _versions.clear();
                            _chainValid = null;
                          });
                        },
                        itemBuilder: (context, index) {"""

    old_snippet2 = """                        itemCount: _filePaths.length,
                        onReorderItem: (oldIndex, newIndex) {
                          setState(() {
                            final item = _filePaths.removeAt(oldIndex);
                            _filePaths.insert(newIndex, item);
                            _versions.clear();
                            _chainValid = null;
                          });
                        },
                        itemBuilder: (context, index) {"""

    content = content.replace(old_snippet2, new_snippet2)
    with open(path, "w") as f:
        f.write(content)

if __name__ == "__main__":
    main()
