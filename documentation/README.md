# Zegel: Explained Like I'm 5 (ELI5)

Welcome to the simple guide to Zegel!

This documentation is written for **absolutely everyone**. You do not need to be a computer scientist, a programmer, or even "good with computers" to understand this. We will use simple everyday examples to explain how Zegel works under the hood to keep your files perfectly safe.

## Table of Contents

1. [What is Zegel? (The Magic Envelope)](01-what-is-zegel.md)
   * The basic idea: what it does and why we need it.
2. [Locking the Safe (Encryption & Keys)](02-locking-the-safe.md)
   * How Zegel locks your files so no one else can read them.
3. [Digital Fingerprints (Hashing & Blocks)](03-digital-fingerprints.md)
   * How Zegel creates a unique signature for your file to know if someone changed it.
4. [The Family Tree of Fingerprints (Merkle Trees)](04-the-family-tree.md)
   * The clever trick Zegel uses to quickly check huge files.
5. [Sharing Secrets (Advanced File Tricks)](05-sharing-and-hiding.md)
   * Splitting keys, hiding parts of a file, and magic reading windows.
6. [Stamps and Traps (Catching Leaks & Adding Signatures)](06-tracking-and-stamps.md)
   * How Zegel catches people who leak files, and how to digitally sign documents.

---

*Note for advanced readers: This guide simplifies highly complex mathematical concepts (like cryptography, AES-256, and SHA-256). If you are looking for the exact technical specifications, please read the `FORMAT_SPEC.md` file in the main folder.*
