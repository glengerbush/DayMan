# DayMan for Linux

This directory contains the Linux application shell and the two explicitly
supported desktop widgets:

- a Tauri 2 WebKitGTK shell for the full DayMan PWA;
- a Plasma 6 plasmoid for desktop and panel use;
- a GNOME Shell 45+ panel extension.

The widgets are intentionally display-only. They read the same versioned
`ClockSnapshot` from the XDG configuration directory, update only the current
time hand once per minute, and launch the full app when clicked.

## Prerequisites

Build the web app first with Node 20.19+:

```sh
npm ci
npm run build:native
```

Install Rust and the normal Tauri 2 Linux prerequisites. On Debian 12 or Ubuntu
22.04 these include `libwebkit2gtk-4.1-dev`, `libappindicator3-dev`,
`librsvg2-dev`, `patchelf`, `build-essential`, `curl`, `wget`, `file`, and
`libssl-dev`. Equivalent `webkit2gtk-4.1`, GTK 3, and librsvg development
packages are needed on Fedora and Arch. Native bundling also needs `dpkg` for
`.deb` output and `rpmbuild`/`rpm-build` for `.rpm` output.

Install the Tauri CLI once:

```sh
cargo install tauri-cli --version '^2' --locked
```

## Build and run

From the repository root:

```sh
platform/linux/scripts/build-app.sh
```

For development, run `npm run dev` at the repository root, then run
`cargo tauri dev` from `platform/linux/` in another terminal.

The Tauri bridge matches `src/lib/platform-bridge.ts` and exposes two narrow
commands:

- `save_dayman_state(state)`
- `read_dayman_state()`

The versioned platform envelope contains the saved location, a fallback
`snapshot`, and a `snapshots` queue covering today plus 31 future local dates.
Writes are atomic and are stored with user-only permissions at:

```text
$XDG_CONFIG_HOME/dayman/dayman-state-v1.json
```

If `XDG_CONFIG_HOME` is unset, `~/.config/dayman` is used. At every
minute-boundary refresh, each Linux widget selects the queued snapshot whose
`dateKey` is the current date in the saved IANA timezone, falling back to
the singular `snapshot` only for legacy state with an absent or empty queue and
only when that snapshot's `dateKey` is today. A non-empty queue without a
current-date match is stale and renders no astronomical data; it never shows an
old or future day as current. This lets the widget roll over at local midnight
for up to 31 days without opening the full app. Shared reference fixtures live in
`fixtures/clock-snapshots/`; the Linux validation also checks them.

## Install the widgets

Install for the current user without root:

```sh
platform/linux/scripts/install-widgets.sh
```

The script installs both widgets when their desktop environment is available.
Use `--plasma` or `--gnome` to select one. It also supports `--prefix` for a
packaging staging root. Removal is symmetrical:

```sh
platform/linux/scripts/uninstall-widgets.sh
```

On Plasma, add “DayMan Clock” from the widget picker. On GNOME, enable
`dayman@dayman.app` with Extensions or:

```sh
gnome-extensions enable dayman@dayman.app
```

Log out and in if GNOME has not discovered a newly installed extension.

## Packages

`scripts/package-native.sh` drives Tauri's `.deb`, `.rpm`, and AppImage
bundlers. Pass a comma-separated subset such as `deb,appimage` when a package
tool is unavailable. Build AppImages on the oldest supported system (Debian 12
or Ubuntu 22.04) to avoid introducing a newer glibc requirement. The Tauri
configuration adds both widget source packages to native packages and places a
copy inside the AppImage. AppImage users still install widgets separately
because an AppImage cannot modify the host desktop.

The Flatpak and AUR definitions are under `packaging/`. See their READMEs for
release-specific preparation. Flatpak deliberately keeps the widgets outside
the sandbox: install them from the release archive with
`install-widgets.sh`, while the sandboxed app writes the snapshot to its
persistent XDG config directory.

The repository does not currently declare a software license, so package
metadata uses `LicenseRef-Proprietary` rather than making an unsupported
open-source claim. Choose a project license, add its root license file, and
update all Linux package metadata before a public release if DayMan is intended
to be open source.

## Validation

Run:

```sh
platform/linux/scripts/validate.sh
cd platform/linux/src-tauri && cargo test
```

The validation script checks JSON/XML metadata, the snapshot fixture against
the documented invariants, shell syntax, GNOME JavaScript syntax, and QML
parsing when the relevant local tools are installed.
