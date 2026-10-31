# Submission 4.5 (build 13)

App Review rejected 4.5 (12) on 21 September 2026 under Guideline 2.1, Information Needed. Items 2 to 6
of their list are answered in the review notes, already in App Store Connect on both platforms. What's
missing is the recording, the new build and the reply.

## State in App Store Connect

| Item | State |
|---|---|
| Header, iOS | Uploaded |
| Search results, iOS | Uploaded |
| Header and search results, macOS | App Store Connect doesn't offer them for Mac |
| Review notes, iOS and macOS | Updated with coffee, suggestions and In-App Purchase |
| Three coffee purchases | Created, 0.99, 2.99 and 4.99 EUR, with review screenshot. Not yet added for review |
| Build | Still 12, with the old icon. Replace with 13 |
| Screenshots | Still the earlier set: on 27.2 the toolbar items are icons, so "Select" and "Add" look different. Run `scripts/export-screenshots.sh` and upload them before submitting |
| App Privacy | Unchanged: Data Not Collected. Check it still reads that way before submitting |

## Recording

Apple asks for a physical device on the latest OS, starting from launching the app, showing the typical
flow and how to reach anything paid. Use fictional accounts only, such as Example Corp. Never show a real
secret or code. One recording for iPhone and one for Mac.

1. Start on the Home Screen, showing the new icon, and open TOTP.
2. Tap +, then Paste the `otpauth://` link from the review notes, and tap Add.
3. Wait for the code to change, then tap the row to copy it.
4. Open the account, add a Fixed Prefix (PIN), and save. Show the PIN badge.
5. Show Select and batch delete on a test account.
6. Show AutoFill being enabled in Settings, and a code filling on a sign-in page.
7. Add the widget to the Home Screen.
8. Open Settings ▸ Help Improve TOTP ▸ Buy Me a Coffee and show the three tips. Show the purchase sheet
   and cancel it, or complete it in sandbox.
9. Tap Send a Suggestion to show it opens GitHub in the browser.
10. Mac only: show the main window, the menu bar item, and Settings (⌘,) ▸ Buy Me a Coffee.

The tips need the build from TestFlight, or a run from Xcode, which uses `StoreKit/Tips.storekit`.

## Draft reply to App Review

> Hello, thank you for the review. The screen recordings are attached, captured on a physical iPhone and
> Mac running the latest OS. The purpose and audience, setup instructions, external services, regional
> behaviour and regulatory information are in the Notes field of App Review Information.
>
> This build also adds three optional consumable in-app purchases (Settings > Buy Me a Coffee), submitted
> with this version. They are tips and unlock nothing, and the app has no account or paid content.

## Steps left

1. Commit, archive and upload build 13 for iOS and macOS (`release-totp` skill).
2. Attach build 13 to both versions.
3. On each coffee purchase, press **Add for Review**.
4. Record, attach the recordings to the reply, and send it.
5. Press **Update Review** on both versions.
