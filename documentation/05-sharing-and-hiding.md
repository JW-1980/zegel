# Sharing Secrets (Advanced File Tricks)

Now that you know how the Zegel magic envelope is locked (Encryption) and sealed (Fingerprints/Merkle Trees), we can talk about the cool tricks you can do with it!

Because of the clever way Zegel chops files into pages, it can do things normal computer files simply cannot do.

## Trick 1: The Treasure Map (Split Keys)

Imagine you have the secret recipe to the world's best cookies. You lock it in a Zegel envelope. If you die, you want your 5 children to open it. But you don't trust any *one* child with the key, because they might steal the recipe for themselves!

Zegel has a feature called **Split Key**. It works like a pirate's treasure map that has been torn into pieces.

You can tell Zegel: "Tear my Master Key into 5 pieces. Give one piece to each child. But, to open the envelope, at least 3 of them must put their pieces together."

If only 2 children try to open it, it stays locked forever. They *must* cooperate and get at least 3 pieces. This is perfect for things like bank vaults or sharing the control of a company.

## Trick 2: Burning a Page (Redaction)

Sometimes you have a file that is mostly okay to share, but contains one terrible secret you want gone forever. Let's say you have a 10-page report, and Page 5 has a list of passwords. You want to give the report to the police, but you absolutely do not want them to see Page 5.

Normally, if you delete a page from a locked file, the whole file breaks (because the fingerprints won't match anymore).

With Zegel, you can perform a **Redaction**. You tell Zegel to "burn" Page 5. Zegel takes the scrambled letters of Page 5 and turns them into pure, useless random noise.

When the police open the file, Pages 1-4 are fine, Page 5 is completely blacked out, and Pages 6-10 are fine. And because of how the Family Tree of fingerprints works, the police can still verify that the rest of the report is 100% authentic and hasn't been tampered with!

## Trick 3: Magic Reading Windows (Selective Disclosure)

This is the opposite of burning a page.

Imagine you have a huge medical record. You go to a foot doctor. The foot doctor only needs to see the pages about your feet (Pages 8 and 9). They have no business reading about your stomach ache on Page 2.

Instead of giving the foot doctor the Master Key to unlock the *whole* envelope, Zegel lets you create a **Selective Disclosure Token**. Think of this as a magic pair of glasses.

You give the doctor the locked file and the magic glasses. When the doctor looks at the file with the glasses, they can *only* see Pages 8 and 9. The rest of the file stays permanently locked.

Even better, you can put a timer on the glasses! You can say, "These glasses will break in 24 hours." After a day, the doctor can never read those pages again.

## What's Next?

We've learned how to share and hide parts of our files. But what if we want to catch a spy? What if someone we trust leaks our secret file to the newspaper?

Zegel has built-in traps to catch them. Let's look at those in: **[Part 6: Stamps and Traps](06-tracking-and-stamps.md)**.
