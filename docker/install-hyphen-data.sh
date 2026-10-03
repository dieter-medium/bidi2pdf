#!/bin/bash
# Installs Chromium's hyphenation dictionaries so that `hyphens: auto` works in the PDFs.
#
# Why this exists: Chromium on Linux does not ship its hyphenation dictionaries in the binary. They
# come as a "Hyphenation" component which the component updater downloads at runtime into
# <user-data-dir>/hyphen-data/<version>/. In our containers that never sticks: chromedriver makes a
# fresh, throw-away user-data-dir for every session (a download would be gone with it), a sandboxed
# remote-chrome has no internet access to download from, and Debian's chromium package (chromium,
# chromium-common) ships no hyphen-data at all. So `hyphens: auto` silently renders as
# `hyphens: manual` - no automatic word breaks, however `lang` is set.
#
# How it works: before looking in the user-data-dir, Chromium's component installer looks for a
# "preinstalled" copy of every component next to its own binary (ComponentInstaller::StartRegistration ->
# FindPreinstallation, rooted at chrome::DIR_COMPONENTS = base::DIR_ASSETS = the directory of the chromium
# executable, /usr/lib/chromium on Debian). It expects <root>/hyphen-data/manifest.json with a valid
# "version" plus the hyph-<locale>.hyb files. That is exactly how Chrome for Testing bundles them
# (chrome/BUILD.gn -> third_party/hyphenation-patterns:bundle_hyphen_data), with the same bogus version
# "1.0.0.0" that is used below. The dictionaries themselves are the AOSP minikin .hyb files that live in
# chromium/src at third_party/hyphenation-patterns/hyb and are fetched from there, pinned to a Chromium tag
# (unchanged since 2023 - the de/en files of 151 and 154 are byte-identical). The pin intentionally does
# not follow the Debian Chromium the image installs: the patterns are data in a format unchanged since
# 2016, updated when the pattern data changes; the hyphenation integration spec, run against the
# image's own Chromium, catches a Chromium that stops reading them.
#
# The component is only registered by the full browser (chrome_browser_main.cc), never by the old
# headless shell - fine for Debian's chromium >= 132, where --headless is the new headless mode - and
# not when --disable-component-update is passed, which neither chromedriver nor bidi2pdf does. Never add it.
#
# Usage: install-hyphen-data.sh [chromium-ref] [target-dir]
set -euo pipefail

ref="${1:-${HYPHEN_DATA_REF:-refs/tags/154.0.8037.92}}"
target="${2:-/usr/lib/chromium/hyphen-data}"
source_dir="third_party/hyphenation-patterns"
archive_url="https://chromium.googlesource.com/chromium/src/+archive/${ref}/${source_dir}.tar.gz"

# The image's language contract: exactly these dictionaries are installed, and each must be in the
# download or the build fails - a renamed or dropped dictionary shows up at build time, not as a silent
# fallback to no hyphenation, and the image does not grow when Chromium adds languages. The archive
# carries ~50; add a language here (and to README "Hyphenation") to support it. Inside Blink "de" maps
# to de-1996, "en" tries en-gb, then en-us
# (third_party/blink/renderer/platform/text/hyphenation/hyphenation_minikin.cc, MapLocale).
dictionaries="hyph-de-1996.hyb hyph-de-1901.hyb hyph-de-ch-1901.hyb hyph-en-us.hyb hyph-en-gb.hyb hyph-fr.hyb hyph-es.hyb hyph-it.hyb hyph-nl.hyb hyph-pt.hyb"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
mkdir -p "${workdir}/src/hyb"

# Gitiles exports a subtree as one tarball. If that is unreachable, fall back to the GitHub mirror of
# chromium/src (tags are mirrored), one file at a time, with the file list taken from the same BUILD.gn
# that Chrome for Testing bundles from.
fetch_from_gitiles() {
  echo "Fetching Chromium hyphenation dictionaries from ${archive_url}"
  curl -fsSL --retry 3 --retry-delay 2 -o "${workdir}/hyb.tar.gz" "${archive_url}" &&
    tar -xzf "${workdir}/hyb.tar.gz" -C "${workdir}/src"
}

fetch_from_github() {
  local raw="https://raw.githubusercontent.com/chromium/chromium/${ref#refs/tags/}/${source_dir}"
  echo "Fetching Chromium hyphenation dictionaries from ${raw}"
  curl -fsSL --retry 3 --retry-delay 2 -o "${workdir}/BUILD.gn" "${raw}/BUILD.gn"
  curl -fsSL --retry 3 --retry-delay 2 -o "${workdir}/src/LICENSE" "${raw}/LICENSE"
  grep -o '"hyb/hyph-[^"]*\.hyb"' "${workdir}/BUILD.gn" | tr -d '"' | sort -u | while read -r file; do
    curl -fsSL --retry 3 --retry-delay 2 -o "${workdir}/src/${file}" "${raw}/${file}"
  done
}

fetch_from_gitiles || { echo "gitiles download failed, trying the GitHub mirror" >&2; fetch_from_github; }

mkdir -p "${target}"
for file in ${dictionaries}; do
  if [ ! -s "${workdir}/src/hyb/${file}" ]; then
    echo "hyphenation dictionary ${file} missing from ${archive_url}" >&2
    exit 1
  fi
  install -m 0644 "${workdir}/src/hyb/${file}" "${target}/${file}"
done
# The patterns are TeX hyphenation patterns under a mix of licenses; keep their notice with the data
# (Chromium's file covers every language, these included).
install -m 0644 "${workdir}/src/LICENSE" "${target}/LICENSE"

# Chromium's component installer only accepts the directory with a manifest carrying a valid version.
# 1.0.0.0 is what Chrome for Testing uses for its bundled copy: lower than anything the component
# updater would ever serve, and not all zeros (that means "no component").
cat > "${target}/manifest.json" <<'EOF'
{
  "manifest_version": 2,
  "name": "hyphens-data",
  "version": "1.0.0.0"
}
EOF
chmod 0644 "${target}/manifest.json"
chmod 0755 "${target}"

dictionaries=("${target}"/*.hyb)
echo "Installed ${#dictionaries[@]} hyphenation dictionaries to ${target}"
