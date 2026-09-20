# CloudKit setup & troubleshooting

Container: `iCloud.com.lucferbux.TOTP` · Database: **private** · Zone: **`TOTPAccounts`** ·
Record type: **`TOTPAccount`**

## How the app syncs

- Accounts are records in the custom `TOTPAccounts` zone of the **private** database. The record
  name is the account's UUID, so the same account keeps one record across devices.
- Reads use **zone change tokens** (`recordZoneChanges(inZoneWith:since:)`), never `CKQuery`.
  This needs **no indexes**, fetches only what changed, and reports deletions from other devices.
- The zone is created on demand; records written by 3.x (in `_defaultZone`) are migrated once, by
  record ID.
- Secrets stay `ChaChaPoly`-sealed. The key is shared between the user's devices through **iCloud
  Keychain**; without it, one device cannot decrypt another's records.

## Releasing a schema change

New fields only reach App Store / TestFlight users after they're deployed:

1. CloudKit Console → container → **Development** → Schema
2. **Deploy Schema Changes…** → review → **Deploy** (to Production)
3. "Record Types (0), Indexes (0)" in that dialog means Production already matches — nothing to do.

The app writes the optional `algorithm` field only for non-SHA-1 accounts, so SHA-1 accounts keep
working against an older schema.

## Browsing records in the Console (optional)

The Console's record browser runs a **query**, so it needs an index the app itself doesn't:

```
Field 'recordName' is not marked queryable
```

To browse records, add the index once:

1. Development → Schema → **Indexes** → `TOTPAccount` → Add Index
2. Field `recordName`, type **QUERYABLE** (add `createdDate` as **SORTABLE** if you want ordering)
3. **Deploy Schema Changes…** → Deploy to Production

Then: Records → Database **Private Database** → Zone **TOTPAccounts** → Record Type `TOTPAccount`
→ Query Records. Private records are only visible for the signed-in iCloud account.

**Never make the app depend on these indexes.** An auto-created schema doesn't have them, which is
what silently broke sync before 4.2.

## Checking sync without the Console

In the app: **Settings → iCloud** shows account status, accounts on this device, accounts in
iCloud, whether the key is shared via iCloud Keychain, the environment, and a **Sync Now** button.

From a development build's logs:

```bash
log show --last 5m --info --predicate 'subsystem == "com.lucferbux.TOTP"' --style compact
```

Useful lines: `iCloud account status: 1` (available), `Fetched N change(s) … M record(s) in iCloud`,
`Sync finished: L local, C in iCloud`.

## Environments

| Build | CloudKit environment |
|---|---|
| Xcode Debug / Run | Development |
| TestFlight / App Store | Production |

A development build and a TestFlight build therefore see **different data**. Test cross-device sync
with the same environment on both devices.

## Known limits

- An account deleted on device B while device A is offline can be re-uploaded by A (last-write-wins).
- HOTP counters aren't merged; the last writer wins.
