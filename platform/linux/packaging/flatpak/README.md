# Flatpak build

The manifest builds the already-generated static web assets and the Rust shell.
It does not fetch JavaScript dependencies inside the Flatpak sandbox.

From the repository root:

```sh
npm ci
npm run build:native
platform/linux/scripts/generate-flatpak-sources.sh
flatpak-builder --force-clean --user --install build-flatpak \
  platform/linux/packaging/flatpak/com.dayman.DayMan.yml
flatpak run com.dayman.DayMan
```

Install `org.gnome.Platform//50`, `org.gnome.Sdk//50`, and the matching
`org.freedesktop.Sdk.Extension.rust-stable` branch from Flathub first. Pin the
exact runtime branches used by the release builder for every tagged release.

Flatpak owns `$XDG_CONFIG_HOME` inside its sandbox, while the desktop widgets
run on the host. The manifest therefore grants only `xdg-config/dayman` and the
bridge uses Flatpak's `HOST_XDG_CONFIG_HOME` to write the same
`dayman/dayman-state-v1.json` read by the host widgets. This is intentionally
narrower than home-directory access. The Plasma and GNOME packages remain host
extensions and are installed from the same release archive with
`platform/linux/scripts/install-widgets.sh`.

Regenerate `cargo-sources.json` whenever `Cargo.lock` changes. The generated
source list contains locked crate URLs and SHA-256 values so Flatpak can build
without network access.
