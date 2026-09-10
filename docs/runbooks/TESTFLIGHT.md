# Installing THRØ on your phone from your phone

Xcode on the Mac is one way to get a build onto the phone. TestFlight is the other: CI builds the app,
signs it and uploads it to App Store Connect; the TestFlight app on the phone offers it; you tap Install.
Once it is set up, nothing needs the Mac. The setup below is done once and takes about twenty minutes,
most of it on Apple's site. Everything you create is yours; nothing here goes into the repository.

The workflow that does the building is `.github/workflows/testflight.yml`. **It has not yet been run
against a real key** — it cannot be, until the secrets below exist — so the first run is the test of it.
If it fails, the log says why, and the section at the end covers the likely reasons.

## What you need

1. **The paid Apple Developer Program.** TestFlight is not available to a free personal team. Check at
   [developer.apple.com/account](https://developer.apple.com/account): under *Membership details* it
   should say *Apple Developer Program* with an expiry date, and the Team ID should be `2XM324WPD5`,
   the team the Xcode project signs with. If it says *Personal Team*, enrol first (a day or two for
   Apple to approve; a yearly fee).
2. **An app record in App Store Connect.** [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
   → *Apps* → the *+* → *New App*: platform iOS; name `THRØ` (App Store names are unique; if it is
   taken, `THRØ Darts` — this is only the store's name, not the product's); primary language English
   (UK); bundle ID `app.thro.darts` — if it is not offered in the list, register it first at
   *Certificates, Identifiers & Profiles* → *Identifiers* → *+* → *App IDs* → *App*, explicit,
   `app.thro.darts`, and tick **App Groups**; SKU `thro-darts`; full access.

   **Tick three capabilities on the App ID: App Groups, Sign in with Apple and Associated Domains.**
   The second and third arrived with accounts (PD-030): the entitlements file asks for both, and an
   archive whose App ID lacks them fails to sign with *Provisioning profile doesn't support the
   Sign in with Apple capability*. Automatic signing usually adds them itself; ticking them by hand
   is the way to be sure.

   **The App Groups tick is new**, and it is what lets the Home Screen and Lock Screen widgets read
   anything at all: the app writes a small file into a shared container and the widget extension
   reads it. If you registered the identifier before this was added, go back to it and tick App
   Groups now — an App ID's capabilities can be edited after the fact. The workflow runs
   `xcodebuild -allowProvisioningUpdates`, which creates the group itself
   (`group.app.thro.darts`) and the extension's own identifier (`app.thro.darts.live`) without
   being asked, so this is the only one to do by hand.
3. **An App Store Connect API key.** *Users and Access* → *Integrations* → *App Store Connect API* →
   *Team Keys* → *+*: name `GitHub Actions`, access **Admin** (automatic signing in CI needs to create a
   distribution certificate; a lesser role cannot). Download the `.p8` file — it can be downloaded once
   only — and note the **Key ID** (ten characters) and the **Issuer ID** (shown above the table).
4. **Three repository secrets.** On github.com (the phone's browser works; the GitHub app does not edit
   secrets): the repository → *Settings* → *Secrets and variables* → *Actions* → *New repository
   secret*, three times:
   - `ASC_KEY_ID` — the Key ID.
   - `ASC_ISSUER_ID` — the Issuer ID.
   - `ASC_KEY_P8` — the whole text of the `.p8` file, from `-----BEGIN PRIVATE KEY-----` to
     `-----END PRIVATE KEY-----`. Open it in a text editor and paste it.
   The key can do a great deal in your Apple account. It lives only in these secrets; if it is ever
   pasted anywhere else, revoke it in App Store Connect and make a new one.
5. **Yourself as a tester.** App Store Connect → the app → *TestFlight* → *Internal Testing* → *+* →
   a group called `Founders` → add your own Apple ID. Install **TestFlight** from the App Store on the
   phone and sign in with the same Apple ID.

## Getting a build from the Mac tonight, without the workflow

The workflow is the way that needs no Mac. With the Mac in front of you the archive takes five
minutes: open `apps/ios/ThroDarts.xcodeproj`, choose the **ThroDarts** scheme and **Any iOS Device
(arm64)** as the destination, check *Signing & Capabilities* shows the team `2XM324WPD5` with
automatic signing for both targets, then **Product → Archive**. When the Organizer opens: **Distribute
App → TestFlight & App Store → Upload**, accept the defaults (automatic signing, upload symbols),
Upload. App Store Connect processes it for five to ten minutes, then TestFlight offers it to the
*Founders* group. Every later upload needs a higher build number: bump `CURRENT_PROJECT_VERSION`
in the project (both targets) before archiving again — the workflow does this for you with its
run number; by hand it is yours to do.

## Getting a build

- **From the phone's browser:** github.com → the repository → *Actions* → *testflight* → *Run workflow*
  → choose the branch (`claude/thro-production-build-je2mkf` until it is merged) → *Run workflow*.
- **From the GitHub app, once this branch is merged:** comment `/testflight` on the pull request. The
  workflow reacts with a rocket, builds the pull request's head, and replies with the build number or a
  link to the log. GitHub only honours comment triggers from the workflow file on the default branch,
  which is why this way waits for the merge.

The run takes about ten minutes. App Store Connect then processes the build for a few more; TestFlight
sends a notification, and the app appears under *Apps* in TestFlight with an *Install* (later *Update*)
button. Each build's number is the workflow's run number, so every upload is newer than the last, and
Settings inside the app still shows the commit it was built from.

## If the run fails

- **"TestFlight is not configured: missing repository secret(s)"** — the first step checks for the three
  secrets and stops. Add the ones it names.
- **A signing or certificate error at "Sign and upload"** — something like *No signing certificate "iOS
  Distribution" found*, *Cloud signing permission error*, or *Provisioning profile … doesn't include
  signing certificate*. Automatic signing in CI creates a cloud-managed Apple Distribution certificate
  when the API key has the Admin role; if your account will not allow that, give the workflow a
  certificate instead. On the Mac: Xcode → *Settings* → *Accounts* → your team → *Manage Certificates*
  → *+* → *Apple Distribution*. Then *Keychain Access* → *My Certificates* → right-click the *Apple
  Distribution: …* certificate → *Export* → `.p12` with a password. In Terminal:
  `base64 -i dist.p12 | pbcopy` copies it. Add two more secrets: `IOS_DIST_P12_BASE64` (paste) and
  `IOS_DIST_P12_PASSWORD`. Run again; the workflow imports the certificate and signs with it.
- **"No App Store Connect record found for the bundle identifier"** or similar — step 2 above was not
  done, or the bundle ID differs from `app.thro.darts`.
- **An "export compliance" question in TestFlight** — the app declares that it uses no non-exempt
  encryption (`ITSAppUsesNonExemptEncryption` is false in `apps/ios/Support/Info.plist`; it makes no
  network connections and encrypts nothing), so this should not appear. If it does, answer *No*.
- **The build is uploaded but TestFlight shows nothing** — App Store Connect can take ten minutes to
  process a first build, and the tester group must contain you (step 5).

## If the widgets are empty on a TestFlight build

The app and the widget extension talk through an App Group, and if the entitlement does not survive
signing the widgets read an empty container and draw nothing — silently, because a widget has no way
to report a problem. **The app says so instead**: Settings → *What you can see on this phone* → the
*Home Screen and Lock Screen widgets* row reads **Blocked** with the reason, rather than **Working**
or **Ready**.

**The run says so too, when it can.** After the upload, the workflow looks inside the signed app
and its widget extension for `group.app.thro.darts` and writes what it found into the run's summary
— *App Group: present in ThroDarts.app*, or a line naming what it is missing from. It reports and
never blocks: everything except the widgets works without it, so refusing to upload an otherwise
good build would be the wrong trade. When the export uploads directly and leaves no file to look
inside, the summary says that rather than implying a pass.

If the widgets are empty: the entitlement is in the source (`apps/ios/Support/ThroDarts.entitlements` and
`apps/ios/SupportLive/ThroLive.entitlements`, held on every push by `tools/check_app_group.py`), so
the loss is in signing, not in the code. Check that the `app.thro.darts` App ID has **App Groups**
ticked (step 2), then run the workflow again — the archive is built unsigned and signed at export,
so a capability added on Apple's side takes effect on the next run with no code change. Nothing else
in the app depends on it: scoring, the Lock Screen, the wall, the share card and the fixtures all
work without it.

## What this does not do

It does not publish anything to the App Store, and it does not sign the app for anyone but your team's
testers. It does not run on its own; every build is one you asked for. It does not change how Xcode on
the Mac works — `CLIENT_IOS.md` still applies, and the Mac remains the way to run a build the moment it
is pushed, without waiting for Apple's processing.
