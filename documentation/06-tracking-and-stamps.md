# Stamps and Traps (Catching Leaks & Adding Signatures)

You have a perfectly locked, tamper-proof file. You know how to share parts of it safely. Now, let's look at the final piece of the puzzle: adding official signatures, and catching people who betray your trust.

## Digital Wax Seals (Attestations)

Imagine you are buying a house. The contract is in a Zegel envelope. How do you prove that the buyer, the seller, and the bank all agreed to the exact same contract?

Zegel uses **Attestations**. Think of an attestation like a personal wax seal stamped onto the outside of the Zegel envelope.

1.  The seller puts their blue wax seal on the envelope that says "I agree to sell."
2.  The buyer puts their red wax seal on it that says "I agree to buy."
3.  The bank puts their gold wax seal on it that says "We approved the loan."

Because the envelope is locked with fingerprints (the Merkle Tree we learned about in Part 4), if *anyone* tries to change the price of the house later, the fingerprints will break, and all three wax seals will instantly shatter. You can always prove exactly who agreed to exactly what file.

## The "Time Bomb" (Expiration)

Sometimes files should only exist for a little while. For example, a company might give an employee a secret file that they are only allowed to read until Friday.

Zegel has an **Expiration** feature. You can set a date on the envelope. Once that date passes, the lock permanently rusts shut. Even if the employee still has the correct Master Key, the file simply refuses to open.

*Note: This relies on the computer telling the correct time. If a very clever bad guy tricks their computer into thinking it is always Thursday, they might be able to keep reading it. But for normal use, it is a great way to enforce rules.*

## Catching Spies (Canary Traps)

This is perhaps the coolest trick of all.

Imagine you are the boss of a company. You have a highly secret report, and you need to send it to three of your managers: Alice, Bob, and Charlie.

A week later, you see your secret report printed on the front page of the newspaper! One of your managers leaked it! But they all swear they are innocent. How do you know who did it?

Zegel uses a trick called a **Canary Trap**. (Miners used to bring canary birds into coal mines to warn them of invisible poison gas).

When you use Zegel to send the report, you don't send the exact same file to all three people.
*   Zegel makes a copy for Alice, and hides a tiny, invisible string of random numbers inside the locking mechanism.
*   It makes a copy for Bob, with a *different* string of invisible numbers.
*   It makes a copy for Charlie, with a *third* string of invisible numbers.

To the managers, the file looks exactly the same. The fingerprint of the text is exactly the same. But the *lock itself* is very slightly different for each person.

When you see the file leaked on the internet, you can download it and ask Zegel: "Whose invisible numbers are hidden in this lock?" Zegel will look at the lock and tell you: *"This file belonged to Bob."*

Spy caught!

---

## Conclusion

You now know how the magic envelope works!
*   **Encryption** (the lock) keeps peeking eyes out.
*   **Hashing and Merkle Trees** (the fingerprints) stop sneaky editors from changing the file.
*   **Split Keys, Redaction, and Selective Disclosure** let you share exactly what you want, when you want.
*   **Attestations, Expiration, and Canary Traps** let you sign contracts, set time limits, and catch spies.

Zegel turns flimsy digital files into strong, reliable, physical-feeling objects. Your secrets are safe!
