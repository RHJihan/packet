#!/bin/sh
# Adapt the upstream source tree to the GNOME version this system ships.
#
# Why this exists
# ---------------
# Upstream Packet is developed against the GNOME runtime it targets in
# build-aux/*.json (GNOME 50 at the time of writing: GTK 4.22 + libadwaita
# 1.9). A .deb, by contrast, links against Debian's own GTK/libadwaita --
# 4.18 and 1.7 on trixie, and those will not change for the life of the
# release.
#
# Bridging that gap used to mean editing upstream-owned files (Cargo.toml,
# the .blp UI, the gresource index), which made every "Sync fork" merge on
# github.com conflict on exactly the lines upstream keeps touching. So the
# same edits happen here instead, at build time. The checked-out tree stays
# byte-identical to upstream, merges stay clean, and everything specific to
# this fork lives in files upstream does not have (debian/, .github/).
#
# Run from debian/rules before dh_auto_configure. Idempotent: a second run,
# or a run on a system new enough not to need anything, changes nothing.
#
# When it fails, it fails loudly. A "pattern not found" error means upstream
# restructured something this script rewrites -- fix it here, not in the
# tree.

set -eu

say() { printf 'gnome-compat: %s\n' "$*"; }
die() { printf 'gnome-compat: error: %s\n' "$*" >&2; exit 1; }

[ -f Cargo.toml ] && [ -d data/resources ] ||
	die "must be run from the source root"

gtk_version=$(pkg-config --modversion gtk4) ||
	die "pkg-config cannot find gtk4 (is libgtk-4-dev installed?)"
adw_version=$(pkg-config --modversion libadwaita-1) ||
	die "pkg-config cannot find libadwaita-1 (is libadwaita-1-dev installed?)"

say "system has GTK $gtk_version, libadwaita $adw_version"

# Rewrite one file, and fail if the pattern we expected was not there.
subst() {
	_file=$1
	_expr=$2
	_before=$(cat "$_file")
	sed -i "$_expr" "$_file"
	[ "$_before" != "$(cat "$_file")" ] ||
		die "pattern not found in $_file: $_expr -- upstream layout changed, update $0"
}

# --------------------------------------------------------------------------
# 1. Clamp the gtk-rs / libadwaita-rs API feature gates.
#
# Those features are hard minimums: system-deps turns features = ["v4_22"]
# into a pkg-config floor of gtk4 >= 4.22, so the build fails before it
# starts. Lowering the gate to what is installed only hides API newer than
# the system has. Crate versions are untouched, so Cargo.lock stays valid.
#
# Only ever clamps downward -- if Debian someday ships more than upstream
# asks for, upstream's own value wins.
# --------------------------------------------------------------------------
clamp_gate() {
	_key=$1        # Cargo.toml dependency key, at start of line
	_prefix=$2     # feature-gate prefix, e.g. v4_
	_version=$3    # system version from pkg-config
	_even=$4       # yes if the library only has even-numbered stable series

	_current=$(sed -n "/^$_key = /s/.*\"\($_prefix[0-9]*\)\".*/\1/p" Cargo.toml |
		head -n1)
	[ -n "$_current" ] ||
		die "no $_prefix* feature gate on the '$_key' line of Cargo.toml"

	_minor=$(echo "$_version" | cut -d. -f2)
	if [ "$_even" = yes ] && [ $((_minor % 2)) -ne 0 ]; then
		_minor=$((_minor - 1))
	fi
	_wanted="$_prefix$_minor"

	if [ "${_current#"$_prefix"}" -le "$_minor" ]; then
		say "$_key gate $_current already fits this system, leaving it alone"
		return 0
	fi

	subst Cargo.toml "/^$_key = /s/\"$_current\"/\"$_wanted\"/"
	say "$_key gate $_current -> $_wanted"
}

clamp_gate gtk v4_ "$gtk_version" yes
clamp_gate adw v1_ "$adw_version" no

# --------------------------------------------------------------------------
# 2. Shortcuts window.
#
# AdwShortcutsDialog / AdwShortcutsSection / AdwShortcutsItem arrived in
# libadwaita 1.8; blueprint-compiler resolves them against the installed
# typelib, so on anything older the .blp does not compile. Swap in the
# GtkShortcutsWindow version kept next to this script, which is upstream's
# own pre-1.8 UI (plus the two entries added since), and point the build,
# the gresource index and the menu item back at it.
#
# gtk/help-overlay.ui is the path GtkApplication loads automatically, and it
# is what registers the win.show-help-overlay action the menu then calls.
# --------------------------------------------------------------------------
if dpkg --compare-versions "$adw_version" ge 1.8; then
	say "libadwaita $adw_version has AdwShortcutsDialog, keeping upstream UI"
elif [ ! -f data/resources/ui/shortcuts-dialog.blp ]; then
	say "no shortcuts-dialog.blp in tree, nothing to swap"
else
	cp debian/gnome-compat/shortcuts.blp data/resources/ui/shortcuts.blp
	rm data/resources/ui/shortcuts-dialog.blp

	subst data/resources/meson.build \
		's|ui/shortcuts-dialog\.blp|ui/shortcuts.blp|'
	subst data/resources/resources.gresource.xml \
		's|alias="shortcuts-dialog\.ui">ui/shortcuts-dialog\.ui|alias="gtk/help-overlay.ui">ui/shortcuts.ui|'
	subst data/resources/ui/window.blp \
		's|"app\.shortcuts"|"win.show-help-overlay"|'
	subst po/POTFILES.in \
		's|ui/shortcuts-dialog\.blp|ui/shortcuts.blp|'

	say "swapped AdwShortcutsDialog UI for the GtkShortcutsWindow one"
fi
