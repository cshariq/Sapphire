#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-test}"
PROJECT_DIR="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
DERIVED_DATA="${SAPPHIRE_TEST_DERIVED_DATA:-$PROJECT_DIR/.local-build/LocalizationTestDerivedData}"
PACKAGES_DIR="${SAPPHIRE_TEST_PACKAGES_DIR:-$PROJECT_DIR/.local-build/SourcePackages}"

case "$MODE" in
  build|test) ;;
  *) echo "usage: $0 [build|test]" >&2; exit 2 ;;
esac

# The XCTest host suppresses Sapphire's normal lifecycle work. This does not
# install an app, register its helper, or grant system permissions.
BUILD_ARGUMENTS=(
  -project "$PROJECT_DIR/Sapphire.xcodeproj"
  -scheme SapphireLocalizationTests -configuration Debug
  -xcconfig "$PROJECT_DIR/config/LocalPublic.xcconfig"
  -derivedDataPath "$DERIVED_DATA"
  -clonedSourcePackagesDirPath "$PACKAGES_DIR"
  -onlyUsePackageVersionsFromResolvedFile
  -destination 'platform=macOS,arch=arm64'
  CODE_SIGNING_ALLOWED=NO
)
if [ "$MODE" = build ]; then
  xcodebuild "${BUILD_ARGUMENTS[@]}" build-for-testing
else
  xcodebuild "${BUILD_ARGUMENTS[@]}" -testLanguage en -testRegion US test
  xcodebuild "${BUILD_ARGUMENTS[@]}" -testLanguage zh-Hans -testRegion CN test
  xcodebuild "${BUILD_ARGUMENTS[@]}" -testLanguage zh-Hans -testRegion US test
fi

APP="$DERIVED_DATA/Build/Products/Debug/Sapphire.app"
INTERMEDIATES="$DERIVED_DATA/Build/Intermediates.noindex/Sapphire.build/Debug"
RESULTS="$DERIVED_DATA/LocalizationResults"
mkdir -p "$RESULTS"
python3 "$PROJECT_DIR/script/localization/test_catalog_check.py"
python3 "$PROJECT_DIR/script/check_localization.py" --app "$APP" \
  --app-stringsdata "$INTERMEDIATES/Sapphire.build/Objects-normal" \
  --app-stringsdata "$INTERMEDIATES/NearbyShare.build/Objects-normal" \
  --widget-stringsdata "$INTERMEDIATES/SapphireAndroidWidgets.build/Objects-normal" \
  | tee "$RESULTS/catalogs.json"
python3 "$PROJECT_DIR/script/test_localization.py" --app "$APP" \
  --output "$RESULTS/native-resources.json"
