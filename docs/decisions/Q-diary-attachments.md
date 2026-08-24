<!-- open -->
**Q-diary-attachments. Photos in diary entries need the envelope over Active Storage.**
Active Storage blobs sit plaintext on disk (or in the D-storage-seam bucket), outside the vault envelope — attaching a photo to a sealed entry would store readable images next to unreadable words. Until the storage seam grows an encryption story (encrypt-at-rest service, or per-blob GCM under the entry's item key), diary entries are text-only and the composer says so. A D-storage-seam conversation, not a diary-local hack.

