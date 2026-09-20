# App Store metadata

Text for the App Store listing, pushed with `fastlane metadata`. Nothing here is ever submitted for
review automatically — the lanes leave the version in *Prepare for Submission* for a human to check.

## Layout, and why it looks asymmetric

App Store Connect scopes fields two ways, and it matters:

| Scope | Fields | Shared between iOS and macOS? |
|---|---|---|
| App-level | `name`, `subtitle`, `privacy_url`, categories | **Yes** — one value serves both |
| Version-level | `description`, `keywords`, `release_notes`, `promotional_text`, `support_url`, `marketing_url`, `copyright`, screenshots | No — per platform |

So the app-level files live **only** in `metadata/ios/`. If both trees carried them, whichever lane
ran last would silently overwrite the other platform's listing.

## Credentials

Auth uses an App Store Connect API key. The `.p8` never belongs in this repo:

```bash
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
```

## Lanes

```bash
fastlane metadata           # push text + screenshots for both platforms (no binary, no submission)
fastlane metadata_text      # text only — quicker while iterating on copy
fastlane screenshots_upload # screenshots only, skipping deliver's metadata step
fastlane precheck_all       # Apple's own metadata checks before you push
fastlane screenshots        # regenerate screenshots from the UI tests
```

`screenshots_upload` exists because deliver's metadata step dies with "No data" when the app has no
App Store review detail yet (fastlane #20538), and it can't create one without a contact phone
number. Fill in `review_information/phone_number.txt` and `email_address.txt` and `metadata` works
on its own again.

Two things no lane does: **attaching the build** to the version, and **`release_notes`** on a first
version — App Store Connect rejects `whatsNew` until there is a released version to describe changes
against.

## Things the API cannot do

These stay manual in App Store Connect, once per app:

- **App Privacy questionnaire** — answer *No, we do not collect data from this app*.
- **EU trader status (DSA)** — required for EU distribution; takes days to verify.
- **Age rating** — everything "None"; the app rates 4+.
- **Pricing, availability and tax category.**
