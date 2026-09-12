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

## Straight onto the phone over Wi-Fi, in about a minute

TestFlight is for testers. For your own phone on your own desk this is faster, needs no upload, no
processing wait and no App Store Connect: the Mac builds and pushes it over the network. The phone
has to be **paired and on the same Wi-Fi** — it already is; Xcode paired it, and it shows up as
`transportType: localNetwork`, which is why the last several builds went on without a cable.

```bash
cd ~/Documents/Thro-Darts-App
xcrun devicectl list devices
```

That prints the phone and its identifier. **Jenson Raper (2)** is
`F2113FA6-D7DA-5720-83C2-DABFABB2D1AD`. Then, in one go — build, install, launch:

```bash
cd ~/Documents/Thro-Darts-App && PHONE=F2113FA6-D7DA-5720-83C2-DABFABB2D1AD && xcodebuild -project apps/ios/ThroDarts.xcodeproj -scheme ThroDarts -configuration Debug -destination "id=$PHONE" -allowProvisioningUpdates -derivedDataPath /tmp/throdevice build && xcrun devicectl device install app --device "$PHONE" /tmp/throdevice/Build/Products/Debug-iphoneos/ThroDarts.app && xcrun devicectl device process launch --device "$PHONE" app.thro.darts
```

It ends with the app opening on the phone. Nothing about it needs Xcode to be running, and none of
it touches the App Store Connect build number, so it can be done as many times as you like.

**If `list devices` does not show the phone:** unlock it and have it on the same Wi-Fi as the Mac.
If it is still missing, plug it in once — pairing survives, and the cable can come out again.

**A build put on this way is a debug build signed for development.** It expires after seven days,
like anything installed without TestFlight, and then wants installing again. That is the trade for
not waiting on Apple.

## Getting a build from the Mac, without the workflow

**The whole thing runs from a terminal. No clicking in Xcode at all.** Three archives were tried by
hand before this section was rewritten, and none of the Xcode-clicking directions in the earlier
version were worth following — two of them described screens that are not in Xcode 26.

```bash
cd ~/Documents/Thro-Darts-App
xcodebuild -project apps/ios/ThroDarts.xcodeproj -scheme ThroDarts \
  -destination 'generic/platform=iOS' -archivePath /tmp/ThroDarts.xcarchive \
  -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath /tmp/ThroDarts.xcarchive \
  -exportOptionsPlist apps/ios/Support/ExportOptions.plist \
  -exportPath /tmp/ThroDartsExport -allowProvisioningUpdates
```

The second command **uploads** — `ExportOptions.plist` says `destination: upload` — so when it ends
there is a build in App Store Connect. It also creates the Apple Distribution certificate and the App
Store profile the first time, which is what `-allowProvisioningUpdates` is for.

Every later upload needs a higher build number: raise `CURRENT_PROJECT_VERSION` in
`apps/ios/ThroDarts.xcodeproj/project.pbxproj` and archive again. It appears **six** times — Debug,
Release and Personal for each of the two targets, the app and its Live Activity extension — and all six
move together, so the app and its extension always carry the same build number. (This line said
"twice" until the Personal configuration and the extension were counted; build 2 was the first to find
out.)

**"exportArchive Failed to Use Accounts" means Xcode on this Mac holds no Apple ID with App Store
Connect access** — the distribution log says *"Failed to find an account with App Store Connect access
for team 2XM324WPD5"*. The archive still succeeds, because signing uses the certificate already in the
keychain; only the upload needs somebody signed in. Xcode → Settings → Accounts → **+** → Apple ID,
with the account's email (not the Team ID), then run the second command again: the archive is kept.

### *"Apple could not finish the sign-in"* on the phone

**This is almost always the installed build, not the code.** Sign in with Apple failing with
`ASAuthorizationError.unknown` — `AuthorizationError Code=1000`, which the app shows as *"Apple could not
finish the sign-in. Check you are signed in to your Apple Account in iPhone Settings"* — happened once
before and the cause was a build **signed before the App ID carried its capabilities**. The entitlement file
in this repository has always been right; what was wrong was the profile the binary on the phone was signed
with.

In order:

1. Check the App ID's capabilities are still ticked (point 1 below). Automatic signing is supposed to
   register them and has not, here, more than once.
2. Delete Xcode's capability and profile caches (point 2 below).
3. **Rebuild and reinstall.** A phone keeps running the old binary until it is replaced, so the symptom
   survives every fix until the app is installed again.
4. Only then suspect the code. The message is generic: iOS gives the same 1000 for a missing capability, a
   device with no Apple Account signed in, and a malformed request.

It cannot be reproduced on a simulator, which is why it has to be worked through in this order rather than
debugged.

### What actually stopped it the first three times

Worth reading before believing any error Xcode prints, because two of the three messages pointed at
the wrong thing.

1. **The App ID's capabilities were not ticked, and Xcode could not tick them.** At
   [developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers)
   → **XC app thro darts** (`app.thro.darts`), the boxes for **App Groups**, **Associated Domains**
   and **Sign In with Apple** were all clear. Tick all three; on the App Groups row press
   **Configure**, tick `group.app.thro.darts`, **Continue**; then **Save** and **Confirm**. The
   sibling identifier `app.thro.darts.live` needs App Groups only, and already had it. Automatic
   signing is *supposed* to register these itself and did not, so check them by hand whenever a
   profile is said to be missing a capability.
2. **Xcode's cached list of what capabilities exist was stale.** The symptom is the strange one:
   *"The capability associated with ASSOCIATED_DOMAINS could not be determined. Please file a bug
   report."* That is not a bug to report. Delete the cache and the archive works:
   ```bash
   rm ~/Library/Developer/Xcode/UserData/Capabilities/capabilities-*-2XM324WPD5-bundle.json
   rm ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision
   ```
   Both are caches. Xcode fetches them again on the next build; nothing is lost.
3. **`error: No Accounts: Add a new account in Accounts settings` is often a lie.** The account was
   already there. Xcode says this when its saved Apple ID session has gone stale — and it raises a
   *Sign in to your Apple Account* sheet to fix it. **That sheet wants the email address**
   (`jensonlewis0@gmail.com`), not the Team ID. `2XM324WPD5` typed into it gives *Your Apple Account
   or password is incorrect*, which reads like a wrong password and is not one. Xcode → Settings →
   Apple Accounts shows whether the account is in: it should list the account with a team under it
   whose role is Agent or Admin.

### The App Store Connect side

The app record already exists — **THRØ**, Apple ID `6810830374`, bundle `app.thro.darts` — so nothing
needs creating. After an upload, [appstoreconnect.apple.com](https://appstoreconnect.apple.com) →
**Apps** → **THRØ** → **TestFlight**: the build shows as *Processing* for five to ten minutes, then
*Ready to Test*. Under **Internal Testing** on the left, **+** makes a group; add yourself by Apple
ID; install **TestFlight** on the phone and sign in with the same Apple ID. `ITSAppUsesNonExemptEncryption`
is already `false` in `apps/ios/Support/Info.plist`, so the export-compliance question is never asked.

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
