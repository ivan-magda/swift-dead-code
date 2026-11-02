#!/usr/bin/env bash
# Style gate: Apple swift-format (layout) and SwiftLint (correctness, idiom, line limit).
#   scripts/lint.sh          check; fails on any formatting difference or lint error
#   scripts/lint.sh --fix    apply swift-format and SwiftLint corrections, then check
#   STRICT=1 scripts/lint.sh also reject SwiftLint warnings
set -euo pipefail

repository_root=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$repository_root"
# shellcheck source=BuildTools/lint-versions.env
source BuildTools/lint-versions.env

fail() {
  printf 'lint: %s\n' "$*" >&2
  exit 1
}

mode=check
case "${1:-}" in
  --fix) mode=fix ;;
  "") ;;
  *) fail "unknown option: $1" ;;
esac

command -v swiftlint >/dev/null 2>&1 || fail 'swiftlint not found'
[[ "$(swiftlint version)" == "$DEADCODE_SWIFTLINT_VERSION" ]] ||
  fail "SwiftLint $DEADCODE_SWIFTLINT_VERSION required, found $(swiftlint version)"
case "$(uname -s)" in
  Darwin) formatter=(xcrun --toolchain XcodeDefault swift-format) ;;
  *) formatter=(swift format) ;;
esac

files=()
while IFS= read -r -d '' file; do
  [[ -f "$file" ]] && files+=("$file")
done < <(git ls-files -z --cached --others --exclude-standard -- \
  'Sources/*.swift' 'Tests/*.swift' Package.swift ':!Tests/Fixtures/**')
[[ ${#files[@]} -gt 0 ]] || fail 'no Swift files selected'

if [[ "$mode" == fix ]]; then
  swiftlint lint --fix --quiet "${files[@]}"
  "${formatter[@]}" format --in-place --configuration .swift-format "${files[@]}"
fi

result=0
"${formatter[@]}" lint --strict --configuration .swift-format "${files[@]}" || result=1
lint_arguments=(lint --quiet)
[[ "${STRICT:-0}" != 1 ]] || lint_arguments+=(--strict)
swiftlint "${lint_arguments[@]}" "${files[@]}" || result=1
[[ "$result" -eq 0 ]] || fail 'style check failed'
printf 'lint: ok\n' >&2
