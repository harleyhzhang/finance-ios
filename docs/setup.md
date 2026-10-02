# Setup

Expect about 15 minutes for the full setup. Every command runs from the repository root.

## 1. Sign the app for your phone

```sh
cp Config/Local.example.xcconfig Config/Local.xcconfig
```

Set a unique `FINANCE_BUNDLE_ID`, your Apple `DEVELOPMENT_TEAM` and, optionally, `FINANCE_OWNER_NAME` for the greeting. `Local.xcconfig` is gitignored. Then run `xcodegen generate`, choose your iPhone in Xcode and press Run. A free Apple account works; those builds expire after 7 days.

The bundle ID also names the app's Keychain items, so keep it stable once you have connected a phone.

## 2. Deploy the backend

```sh
npx convex dev --once --configure new   # creates a project and writes .env.local
npx convex deploy                       # deploys convex/ to production
```

Your endpoint is `https://<deployment>.convex.site/v1/snapshot`. You can find the deployment name in the Convex dashboard.

## 3. Create keys

```sh
node Tools/finance.ts init-keys              # random read token + AES key, saved in your Mac Keychain
node Tools/finance.ts configure-read-token   # stores only the token's SHA-256 in Convex
```

## 4. Build a snapshot

Export balances into two CSVs shaped like [`examples/`](../examples), then convert them:

```sh
node Tools/finance.ts from-csv accounts.csv history.csv 1.36 ~/finance/snapshot.json
```

The arguments are the accounts file, the history file (or `-` for none), the CAD per USD rate and the output path. Output must live outside the repository. See [data.md](data.md) for the format.

## 5. Publish

```sh
node Tools/finance.ts prepare ~/finance/snapshot.json ~/finance/envelope.json   # validate + encrypt
node Tools/finance.ts status                                                    # current revision
node Tools/finance.ts publish ~/finance/envelope.json <revision>                # upload
node Tools/finance.ts verify-remote https://<deployment>.convex.site/v1/snapshot
```

`publish` fails if someone published after you ran `status`. If that happens, rerun `status` and try again.

## 6. Connect the phone

```sh
node Tools/finance.ts profile https://<deployment>.convex.site/v1/snapshot ~/finance/phone.financeprofile
```

AirDrop the file to your phone and open it with Finance. The app moves the secrets into its Keychain. Delete every copy of the profile afterwards, because it contains your key. Pull down on the dashboard to refresh.

## Updating

Repeat steps 4 and 5 whenever balances change. The phone keeps showing its last good snapshot until a refresh succeeds.
