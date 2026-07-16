#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

Scripts/check-public-repo-safety.sh

xcodebuild \
  -project SomaFM.xcodeproj \
  -scheme SomaFM \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_IDENTITY= \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build
