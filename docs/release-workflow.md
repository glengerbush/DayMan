# Release workflow

The `Build release` GitHub Actions workflow runs whenever a stable semantic-version
tag such as `v0.1.0` is pushed. It can also be run manually against an existing tag
from **Actions → Build release → Run workflow**.

Linux `.deb`, `.rpm`, `.AppImage`, `.pkg.tar.zst`, and widget archives are
always built. The ad-hoc-signed macOS DMG is also always built. Android is
added when its signing-bundle secret is configured. The final job creates the
GitHub Release, attaches every available package, and generates `SHA256SUMS`.

## Android signing secret

An Android APK must be signed even when it is installed directly and never
published through an app store. Generate a passwordless signing bundle once:

```sh
platform/android/scripts/create-signing-bundle.sh
```

Keep `dayman-android-signing.tar.gz` private and backed up. Android will reject
future updates signed with a different key. Encode it as one line:

```sh
base64 -w 0 dayman-android-signing.tar.gz
```

Save the result as the GitHub Actions repository secret
`DAYMAN_ANDROID_SIGNING_BUNDLE_BASE64`. The workflow builds an unsigned release
APK, aligns it, signs it with `apksigner`, and verifies the signature. It does
not use a keystore password, Play Store account, or Android App Bundle.

With GitHub CLI authenticated for this repository, the secret can be set
directly:

```sh
base64 -w 0 dayman-android-signing.tar.gz |
  gh secret set DAYMAN_ANDROID_SIGNING_BUNDLE_BASE64
```

## macOS distribution

The workflow builds the app and widget without an Apple development team,
ad-hoc signs both targets, and packages an unnotarized DMG. There are no macOS
secrets. After dragging the app into Applications, users must clear its
quarantine attributes before opening it:

```sh
xattr -cr /Applications/DayMan.app
```

The full app works with this distribution model. The current WidgetKit
extension cannot share the app's selected location in an ad-hoc build because
Apple requires a provisioned App Group for that shared container. The release
build strips the unauthorized App Group entitlement so macOS can launch the
app reliably; the widget remains unconfigured. Supporting the widget without
an Apple developer account would require replacing its shared-container
architecture.

## Publishing a version

Create and push the tag after the release commit is on `main`:

```sh
git tag v0.1.0
git push origin v0.1.0
```

For a tag that already exists, run the workflow manually and enter that exact tag.
If a release for the tag already exists, the workflow updates its assets rather
than creating a duplicate.
