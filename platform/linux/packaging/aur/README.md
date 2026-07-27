# AUR publishing

Before publishing:

1. Create and push the matching `v0.1.0` source tag.
2. Replace `SKIP` in `PKGBUILD` with the archive SHA-256.
3. Run `updpkgsums`, `makepkg --printsrcinfo > .SRCINFO`, then
   `makepkg --cleanbuild --syncdeps`.
4. Publish `PKGBUILD` and `.SRCINFO` to the AUR `dayman` repository.

The package installs the app and both widgets. Plasma and GNOME are optional
dependencies so the package remains usable on other desktop environments.
