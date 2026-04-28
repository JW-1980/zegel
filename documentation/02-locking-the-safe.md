# Locking the Safe (Encryption & Keys)

In the last part, we said Zegel is like a magic envelope. But what keeps people from just ripping the envelope open? The answer is a very strong, invisible lock. In computer words, this lock is called **Encryption**.

## How the Lock Works (Scrambling)

Imagine taking your secret letter and putting it through a very special paper shredder. But instead of cutting it into pieces, this machine turns every single letter into a random symbol.

*   The word "Hello" might turn into `%x@9L`.
*   The number "100" might turn into `^$z`.

This scrambling process is what computers call "Encryption". When your file is scrambled like this, anyone who peeks at it just sees garbage.

Zegel uses a specific type of scrambling machine called **AES-256**. You don't need to remember the name, but just know that it is the exact same super-strong lock used by banks, the military, and governments around the world to protect their top secrets. It is incredibly tough!

## The Key to the Lock

If your file is scrambled, how do you (or your friend) ever read it again? You need the **Master Key**.

The Master Key is the only thing that can run the scrambling machine backwards to turn `%x@9L` back into "Hello".

In Zegel, a Master Key is just a very long, very random string of letters and numbers. It usually looks something like this: `a1b2c3d4e5f6...`

If you lose this exact key, your file is locked forever. Not even the creator of Zegel can open it for you.

## What if I just want to use a Password?

Keys that look like `a1b2c3d4e5f6...` are hard for humans to remember. You probably just want to type a password, like "MySecretDog123!".

Zegel lets you use a password! But because the AES-256 scrambling machine *only* accepts long, random keys, Zegel has to do a trick.

It takes your simple password ("MySecretDog123!") and puts it through a "stretching machine" (called Argon2). This machine stretches and mixes your password until it turns into a long, strong Master Key.

## A Pinch of Salt

There's one more clever trick Zegel uses.

Imagine two people use the exact same password: "Password123". Normally, the stretching machine would make the exact same Master Key for both of them. This is bad, because if someone guesses the key for the first file, they can open the second file too!

To fix this, every time you lock a file with Zegel, it throws in a pinch of invisible, random "salt".

The stretching machine mixes your password *and* the random salt together. This means even if you use "Password123" on ten different files, each file gets a totally unique mix, and a totally unique Master Key.

## What's Next?

So now we know how Zegel scrambles your file so no one can read it. But we also said Zegel makes sure no one can *change* your file. How does it know if a sneaky mailman tried to tamper with the locked box?

Let's find out in: **[Part 3: Digital Fingerprints](03-digital-fingerprints.md)**.
