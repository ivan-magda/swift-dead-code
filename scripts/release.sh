#!/usr/bin/env bash
# Builds the release artifacts of one version into a directory:
#   swift-dead-code-VERSION-macos.zip            the universal binary and LICENSE, for Homebrew
#                                                and manual installs
#   swift-dead-code-VERSION.artifactbundle.zip   the same binary as a SwiftPM artifact bundle,
#                                                for swift-dead-code-plugin
#   checksums.txt                                SHA-256 of both, which is also SwiftPM's checksum
#
#   scripts/release.sh VERSION OUTPUT_DIRECTORY
set -euo pipefail

fail() {
  printf 'release: %s\n' "$*" >&2
  exit 1
}

[[ $# -eq 2 ]] || fail 'usage: scripts/release.sh VERSION OUTPUT_DIRECTORY'
version=$1
mkdir -p "$2"
output=$(cd "$2" && pwd -P)
repository_root=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$repository_root"

build=(swift build -c release --arch arm64 --arch x86_64)
"${build[@]}"
binary="$("${build[@]}" --show-bin-path)/swift-dead-code"
built=$("$binary" --version)
[[ "$built" == "$version" ]] || fail "the binary reports version $built, not $version"

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
archive="swift-dead-code-$version-macos.zip"
bundle_archive="swift-dead-code-$version.artifactbundle.zip"
rm -f "$output/$archive" "$output/$bundle_archive" "$output/checksums.txt"

mkdir "$stage/archive"
cp "$binary" LICENSE "$stage/archive/"
(cd "$stage/archive" && zip -q "$output/$archive" swift-dead-code LICENSE)

bundle="$stage/swift-dead-code.artifactbundle"
mkdir -p "$bundle/swift-dead-code-$version-macos/bin"
cp "$binary" "$bundle/swift-dead-code-$version-macos/bin/"
cp LICENSE "$bundle/"
cat >"$bundle/info.json" <<EOF
{
  "schemaVersion": "1.0",
  "artifacts": {
    "swift-dead-code": {
      "version": "$version",
      "type": "executable",
      "variants": [
        {
          "path": "swift-dead-code-$version-macos/bin/swift-dead-code",
          "supportedTriples": ["x86_64-apple-macosx", "arm64-apple-macosx"]
        }
      ]
    }
  }
}
EOF
(cd "$stage" && zip -qr "$output/$bundle_archive" swift-dead-code.artifactbundle)

(cd "$output" && shasum -a 256 "$archive" "$bundle_archive" >checksums.txt)
cat "$output/checksums.txt"
