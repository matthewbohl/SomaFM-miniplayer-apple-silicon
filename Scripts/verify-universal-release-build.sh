#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

Scripts/check-public-repo-safety.sh

derived_data_path="${SOMAFM_DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/SomaFM-Universal-DerivedData}"
app_path="$derived_data_path/Build/Products/Release/SomaFM miniplayer.app"
binary_path="$app_path/Contents/MacOS/SomaFM miniplayer"
privacy_manifest_path="$app_path/Contents/Resources/PrivacyInfo.xcprivacy"
entitlements_path="Supporting-files/SomaFM.entitlements"

xcodebuild \
  -project SomaFM.xcodeproj \
  -scheme SomaFM \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_data_path" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY= \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

architectures=$(lipo -archs "$binary_path")
for architecture in arm64 x86_64; do
  case " $architectures " in
    *" $architecture "*) ;;
    *)
      echo "error: universal build is missing $architecture" >&2
      exit 1
      ;;
  esac
done

minimum_os_slices=$(vtool -show-build "$binary_path" \
  | awk '$1 == "minos" && $2 == "13.0" { count += 1 } END { print count + 0 }')
if [ "$minimum_os_slices" -ne 2 ]; then
  echo "error: both executable slices must target macOS 13.0" >&2
  vtool -show-build "$binary_path" >&2
  exit 1
fi

if [ "$(plutil -extract LSMinimumSystemVersion raw "$app_path/Contents/Info.plist")" != "13.0" ]; then
  echo "error: built Info.plist must require macOS 13.0" >&2
  exit 1
fi

if [ "$(plutil -extract ITSAppUsesNonExemptEncryption raw "$app_path/Contents/Info.plist")" != "false" ]; then
  echo "error: built Info.plist must declare that the app uses no non-exempt encryption" >&2
  exit 1
fi

if [ "$(plutil -extract NSAppTransportSecurity.NSAllowsArbitraryLoadsForMedia raw "$app_path/Contents/Info.plist")" != "true" ]; then
  echo "error: built Info.plist must allow non-ATS AVFoundation media streams" >&2
  exit 1
fi

if plutil -extract NSAppTransportSecurity.NSAllowsArbitraryLoads raw "$app_path/Contents/Info.plist" >/dev/null 2>&1; then
  echo "error: built Info.plist must not allow arbitrary network loads" >&2
  exit 1
fi

for entitlement in 'com\.apple\.security\.app-sandbox' 'com\.apple\.security\.network\.client'; do
  if [ "$(plutil -extract "$entitlement" raw "$entitlements_path")" != "true" ]; then
    echo "error: required entitlement is disabled: $entitlement" >&2
    exit 1
  fi
done

if [ ! -f "$privacy_manifest_path" ]; then
  echo "error: built app is missing PrivacyInfo.xcprivacy" >&2
  exit 1
fi

plutil -lint "$privacy_manifest_path"
echo "Universal Release verification passed: $architectures, macOS 13.0+."
