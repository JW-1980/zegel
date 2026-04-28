# Digital Fingerprints (Hashing & Blocks)

We know Zegel locks your file so no one can read it. But what if someone doesn't want to *read* it, they just want to *destroy* it? What if they take your locked file and just flip a few random switches inside to break it?

Zegel needs a way to know if even a tiny piece of your file was messed with. It does this using **Digital Fingerprints**.

## What is a Digital Fingerprint? (Hashing)

Every person in the world has a unique fingerprint. If you leave your fingerprint on a glass, a detective knows exactly who held it.

Computers can make fingerprints for files, too! This process is called **Hashing**.

Imagine a magical machine. You feed a book into this machine, and it spits out a short, unique code. Let's say the code for the book "Harry Potter" is `A82B`.

This machine has two very strict rules:
1.  **Always the same:** If you feed "Harry Potter" into the machine a million times, it will always spit out `A82B`.
2.  **Tiny changes make huge differences:** If you take "Harry Potter", erase *one single comma* on page 100, and feed it into the machine again, the code will completely change. It won't be `A82C`; it will be something totally different, like `X99F`.

Zegel uses a super-strong fingerprint machine called **SHA-256**.

When Zegel locks your file, it takes a fingerprint of the whole thing and writes that fingerprint on the outside of the envelope. When your friend opens the file, Zegel takes a *new* fingerprint. If the new fingerprint perfectly matches the one on the envelope, the file is safe. If it doesn't match, the magic seal is broken, and Zegel shouts: "Tampering detected!"

## Chopping the Book into Pages (Blocks)

Now, imagine you have a gigantic file. Let's say it's a huge 5-hour movie.

If someone changes one tiny pixel in the middle of the movie, the fingerprint for the *whole movie* changes. That's good! But to check the fingerprint, Zegel would have to read the entire 5-hour movie from start to finish. That would take a very long time.

To fix this, Zegel uses a clever trick. It doesn't look at your file as one giant object. It chops your file into smaller pieces, called **Blocks**.

Think of blocks like the pages of a book. Instead of taking one fingerprint for the whole heavy book, Zegel takes a separate fingerprint for *every single page*.

*   Page 1 gets a fingerprint.
*   Page 2 gets a fingerprint.
*   Page 3 gets a fingerprint.

If a sneaky mailman changes a word on Page 2, Zegel doesn't have to read the whole book to find out. It just looks at the fingerprint for Page 2, sees that it changed, and instantly knows exactly where the bad guy messed with the file!

## What's Next?

Chopping a file into pages (blocks) is smart, but it creates a new problem. If your book has 1,000 pages, you now have to keep track of 1,000 different fingerprints! How does Zegel organize all these fingerprints without getting confused?

It uses a very special tree structure. Let's explore that in: **[Part 4: The Family Tree of Fingerprints](04-the-family-tree.md)**.
