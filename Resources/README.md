# Mouse artwork

Run `bash scripts/fetch-artwork.sh` from the repository root to download the two mouse images directly from Angry Miao and verify their SHA-256 hashes. The images are not bundled in the source repository and are not MIT-licensed. See [third-party notices](../THIRD_PARTY_NOTICES.md).

An optional `AppIcon-v1.png` supplies a custom release icon. If absent, `build.sh` generates a simple fallback from `scripts/MakeFallbackIcon.swift`, so a fresh source checkout can build without private files.
