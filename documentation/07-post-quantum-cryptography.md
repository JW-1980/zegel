# Post-Quantum Cryptography (PQC)

In the previous parts, we talked about AES-256 and how strong it is. But what happens if computers get a million times faster overnight?

There is a new type of computer being built called a **Quantum Computer**. These machines use quantum physics to do some math problems instantly. Once they get powerful enough, they could theoretically crack the locks (like RSA or ECC) that the internet uses to stay safe today.

## Why Do We Need PQC?

If an attacker steals a locked file today, they can't read it. But they could just keep it on their hard drive and wait 10 or 20 years until they have a powerful Quantum Computer to break it open. This is called "Store Now, Decrypt Later".

Zegel already uses **AES-256** and **SHA-256**, which experts say are naturally resistant to quantum computers. A quantum computer would only make attacking AES-256 slightly faster, but it would still take longer than the age of the universe!

However, for things like digital signatures (signing who made the file) and exchanging keys, quantum computers could break them easily. This is why Zegel employs **Post-Quantum Cryptography (PQC)**.

## What is PQC?

**Post-Quantum Cryptography (PQC)** is a fancy way of saying "new math that even quantum computers can't easily solve."

Think of normal math locks as a maze. A normal computer tries every path one by one. A quantum computer can magically look at all paths at once and instantly find the exit.

PQC changes the maze into something entirely different—like a maze that constantly changes shape or uses crazy geometry (called "Lattices"). Even if a quantum computer tries its magic trick, it still gets hopelessly lost.

## How Zegel Uses It

Zegel integrates special PQC algorithms (like **Kyber / ML-KEM** for secret sharing and **Dilithium / ML-DSA** for signatures).

Because these new locks are added into Zegel, you don't have to worry about a super-computer breaking into your files in the future. It’s like adding an invisible force field to our magic envelope!
