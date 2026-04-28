# Technical Concerns & Observations

While drafting the ELI5 documentation for the Zegel format, a few potential edge cases and security nuances were noted regarding the implementation as described in the `FORMAT_SPEC.md`.

## 1. Expiration Time Spoofing
The documentation mentions that expiration dates are checked against the current time (Step 8 of Verification: `If FLAG_HAS_EXPIRATION: check current time < expiration timestamp`).
*   **Concern:** If a user possesses the Master Key and the encrypted `.zgl` file, and the expiration validation relies solely on the host machine's local system clock, a malicious actor could simply change their OS system time to a date prior to the expiration timestamp to bypass the restriction.
*   **Recommendation:** While this is a known limitation of client-side DRM/expiration without a trusted time server, it should be heavily emphasized in the technical documentation that Expiration is a *policy enforcement* tool for honest actors, not a cryptographically hard guarantee against a determined adversary with local machine control.

## 2. Canary Trap Evasion (Re-encryption)
Canary Traps work by embedding a unique identifier (padding) into the ciphertext during the encryption process, which does not alter the Merkle root of the plaintext.
*   **Concern:** If a malicious recipient ("Bob") receives his unique, canary-trapped `.zgl` file and the Master Key, he can extract the raw plaintext. If Bob then *re-seals* that plaintext using his own instance of Zegel (generating a new `.zgl` file with a new salt, new IVs, new Master Key, and no canary padding), the leaked file will no longer contain the canary identifying him.
*   **Recommendation:** Canary traps are primarily effective against naive leaking (simply forwarding the `.zgl` file or performing a raw dump without re-encryption). It should be noted that determined adversaries who extract and re-encode the plaintext will strip the canary metadata.

## 3. Redaction vs Original Hash
When a block is redacted, its ciphertext is replaced with random bytes.
*   **Concern:** The `FORMAT_SPEC.md` mentions that applications can store the `original_hash` of the file in the metadata. If a file is redacted, the Merkle root remains valid (because the redacted block is skipped during decryption validation), but the overall hash of the extracted *plaintext* will no longer match the `original_hash` stored in the metadata.
*   **Recommendation:** Ensure the application layer clearly distinguishes between "File Integrity" (Merkle root is intact) and "Content Integrity" (Extracted plaintext matches original hash), as redactions intentionally break the latter while preserving the former.

## 4. Selective Disclosure & File Context
*   **Concern:** When using Selective Disclosure, providing only a subset of blocks (e.g., Block 8 and 9) might inadvertently leak context if the blocks cut off mid-sentence or mid-data structure. For example, if a JSON object spans blocks 7, 8, and 9, extracting only 8 and 9 might result in unparseable JSON.
*   **Recommendation:** Applications implementing Zegel should ideally align block boundaries with logical data boundaries (if possible) or handle partial/truncated data gracefully when presenting selectively disclosed files to the user.
