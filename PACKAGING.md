# Debian packaging for this fork

This fork carries two additions on top of upstream Packet: a `debian/` directory (native Debian packaging) and `.github/workflows/release-deb.yml` (a manually triggered build-and-release workflow). Together they produce a `.deb` that installs cleanly on Debian 13 (trixie) with GNOME 48.

## Releasing

Go to Actions, pick "Release (.deb)", and press Run workflow. Leave the version field empty to release whatever version `meson.build` declares, or type a version like `0.6.2` to override it. The workflow refuses to run if the tag already exists, so you cannot accidentally overwrite a release. When the run finishes, the release page contains `packet_<version>_amd64.deb`, a `SHA256SUMS` file, and the `.changes`/`.buildinfo` build metadata. Install with:

    sudo apt install ./packet_<version>_amd64.deb

Installing through apt (not dpkg -i) resolves the runtime dependencies automatically.

## How the pieces fit

The build runs inside an official `debian:trixie` container so the binary links against Trixie's exact glibc, GTK4, and libadwaita. `dpkg-buildpackage` reads `debian/rules`, which hands the whole build to debhelper's Meson integration; nothing about the upstream build is duplicated or patched. `dh_shlibdeps` inspects the finished binary and writes the `Depends:` field from the shared libraries it actually links, which is what guarantees a clean install on a stock Trixie system. The workflow then installs the freshly built package inside the same pristine container as a smoke test before anything is published.

The Rust toolchain comes from rustup (stable) rather than apt, because Packet's crate graph can require a newer compiler than Debian ships. To freeze the toolchain for reproducible rebuilds, pin `RUST_TOOLCHAIN` in the workflow to an exact version. The `.buildinfo` asset records every Debian package version present at build time, and `Cargo.lock` pins the crate graph, so a past release can be reconstructed faithfully.

## Maintenance notes

`debian/changelog` in the repo is a placeholder for local builds; CI regenerates it per release. `debian/rules` must stay executable (`git update-index --chmod=+x debian/rules` if it ever loses the bit; CI also chmods it defensively). If upstream adds a new native build dependency, add it in two places: the apt install list in the workflow and `Build-Depends` in `debian/control`. Lintian output appears in the build log; it is informational and never fails the build.

## Local build (optional)

On a Trixie machine or container:

    sudo apt install build-essential debhelper meson ninja-build pkgconf \
      libglib2.0-dev libgtk-4-dev libadwaita-1-dev desktop-file-utils \
      appstream gettext protobuf-compiler libssl-dev cargo
    dpkg-buildpackage -b -us -uc

The `.deb` appears in the parent directory.
