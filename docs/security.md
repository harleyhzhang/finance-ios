# Security

**What Convex sees:** AES-256-GCM ciphertext, revision numbers, timestamps, lengths and digests. It never sees balances, account names or the key.

**Reads:** `GET /v1/snapshot` requires a 256-bit bearer token. Convex stores only the token's SHA-256. Missing or wrong tokens get 401, and missing server configuration gets 503. There is no HTTP write route. Publishing goes through the authenticated Convex CLI and an internal mutation.

**Keys:** the Mac keeps the read token and encryption key in Keychain and passes them to helpers over pipes. The phone stores them in Keychain as `WhenUnlockedThisDeviceOnly`. A `.financeprofile` holds both secrets in plaintext, so treat it like a password and delete it once it has been imported.

**Phone:** the app opens offline from its cache, which is stored with complete file protection. Refresh makes one request with cookies, caching and redirects disabled. A failed fetch, decrypt or validation leaves the last good cache in place. The app rejects older revisions and older capture times.

**Rotation:** to rotate the read token, create new credentials, run `configure-read-token` and import a new profile. Losing the encryption key makes old ciphertext unreadable, so republish from your source data.

**Repo hygiene:** `Tools/check_private_files.py` blocks profiles, local config and seed files from being committed. It is not a full secret scanner, so review diffs before you push.
