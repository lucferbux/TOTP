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
| Three coffee purchases | Created, 0.99, 2.99 and 4.99 EUR, with review screenshot. In the iOS draft submission |
| Build | 13 attached on iOS and macOS |
| Screenshots, iOS | Replaced from iOS 27.2: iPhone, iPad and iPhone Duo's outer display |
| Screenshots, iPhone Duo inner display | Not taken: it has to be opened in Device Hub first (`scripts/export-screenshots.sh --duo-inner`) |
| Screenshots, macOS | Replaced from macOS 27.2 |
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

Paste this into the Reply field, then use Attach File for the two recordings. It answers Apple's six
points in their order. It has to stay under the field's 4,000 characters.

```text
Hello, and thank you for the review. Here is the information you requested for TOTP Password 4.5 (build 13), on iOS and macOS. The same details are in the Notes field of App Review Information.

1. SCREEN RECORDING
Two recordings are attached: one from a physical iPhone on iOS 27.2 and one from a physical Mac on macOS 27.2. Each begins by launching the app and shows the typical flow.
The app has no registration, login, account deletion or user-generated content, so the recordings show none. No content or feature is paid. The only purchases are three optional tips, and the recordings show how to reach them: Settings > Help Improve TOTP > Buy Me a Coffee.

2. PURPOSE AND AUDIENCE
TOTP Password is a general-purpose two-factor authenticator for anyone who has turned on two-factor authentication for their online accounts. Email, cloud and developer sites, among others, ask for a six-digit code at sign-in, and the app generates those codes on the device using the open standards RFC 6238 (TOTP) and RFC 4226 (HOTP). It saves people from typing codes by hand with AutoFill, widgets and a Mac menu bar item, and it keeps their accounts in sync through their own private iCloud. It is not built for, or restricted to, any company or organisation.

3. HOW TO TRY IT
No credentials or sample files are needed, and the app works offline as soon as it opens.
a) Copy this link, tap + and choose Paste. It contains the public RFC 6238 test secret, not a real account:
otpauth://totp/Example%20Corp:reviewer@example.com?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=Example%20Corp
b) Tap Add. A code appears and refreshes every 30 seconds. Tap the row (Mac: click it) to copy the code.
c) PIN prefix: open the account, fill in Fixed Prefix (PIN) and save. The row shows a PIN badge, and copying now gives PIN + code.
d) Tap Select to choose several accounts and delete them together.
e) AutoFill: in iOS Settings or macOS System Settings, go to General > AutoFill & Passwords and enable TOTP.
f) Widgets: add TOTP from the widget gallery.
g) Settings > Help Improve TOTP: Send a Suggestion opens a public GitHub page in the browser, and Buy Me a Coffee lists the three tips.
On Mac, the app also lives in the menu bar: the shield icon lists every code, and Open TOTP brings the window back after it is closed.

4. EXTERNAL SERVICES
- Apple iCloud: a private CloudKit database in the user's own iCloud account for sync, and iCloud Keychain for the encryption key.
- Apple In-App Purchase: the optional tips.
There are no servers of ours, third-party SDKs, analytics, advertising, other payment processors or AI services. Codes are computed on the device with CryptoKit.

5. REGIONS
The app functions consistently across all regions, with no regional differences in features or content.

6. REGULATION AND THIRD-PARTY MATERIAL
The app does not operate in a regulated industry and contains no protected third-party material, so no documentation applies. It implements open IETF standards, and users add secrets issued to them by their own services.

CHANGES IN THIS BUILD
Build 13 adds the three optional consumable tips, submitted with this version, and a link for sending suggestions. The tips unlock nothing.

Please let me know if you need anything else. Thank you.
```

## Steps left

The first in-app purchases can only go to review together with an app version. Both versions were submitted
without them on 1 November, so those submissions were cancelled. The reply and its recordings stay on the
cancelled submissions, so new ones need the recordings in App Review Information.

1. In each version's App Review Information, add its recording to Attachment and press Save: `totp.MP4` on
   iOS, `totp-mac.mov` on macOS. `fastlane review_attachments ios:<path> mac:<path>` does the same.
2. Submit the iOS draft (version and three coffees), then the macOS draft.
