#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

failed=0

report() {
  printf 'error: %s\n' "$1" >&2
  failed=1
}

if git ls-files --error-unmatch Config/Signing.local.xcconfig >/dev/null 2>&1; then
  report "Config/Signing.local.xcconfig must not be tracked"
fi

tracked_signing_material=$(git ls-files | grep -E '\.(cer|mobileprovision|p12|provisionprofile)$' || true)
if [ -n "$tracked_signing_material" ]; then
  printf '%s\n' "$tracked_signing_material" >&2
  report "private signing material must not be tracked"
fi

invalid_team_settings=$(grep -n 'DEVELOPMENT_TEAM = ' SomaFM.xcodeproj/project.pbxproj \
  | grep -Fv '$(SOMAFM_DEVELOPMENT_TEAM)' || true)
if [ -n "$invalid_team_settings" ]; then
  printf '%s\n' "$invalid_team_settings" >&2
  report 'Xcode development teams must use $(SOMAFM_DEVELOPMENT_TEAM)'
fi

invalid_identity_settings=$(grep -n 'CODE_SIGN_IDENTITY = ' SomaFM.xcodeproj/project.pbxproj \
  | grep -Fv '$(SOMAFM_CODE_SIGN_IDENTITY)' || true)
if [ -n "$invalid_identity_settings" ]; then
  printf '%s\n' "$invalid_identity_settings" >&2
  report 'Xcode signing identities must use $(SOMAFM_CODE_SIGN_IDENTITY)'
fi

invalid_profile_settings=$(grep -n 'PROVISIONING_PROFILE_SPECIFIER = ' SomaFM.xcodeproj/project.pbxproj \
  | grep -Fv '$(SOMAFM_PROVISIONING_PROFILE_SPECIFIER)' || true)
if [ -n "$invalid_profile_settings" ]; then
  printf '%s\n' "$invalid_profile_settings" >&2
  report 'Xcode provisioning profiles must use $(SOMAFM_PROVISIONING_PROFILE_SPECIFIER)'
fi

user_root='/''Users/'
home_root='/''home/'
local_paths=$(git grep -n -F -e "$user_root" -e "$home_root" -- \
  ':(exclude)Scripts/check-public-repo-safety.sh' || true)
if [ -n "$local_paths" ]; then
  printf '%s\n' "$local_paths" >&2
  report "tracked files must not contain absolute user home paths"
fi

private_markers=$(git grep -n -E \
  'BEGIN (OPENSSH|RSA|EC|DSA) PRIVATE KEY|github_pat_[A-Za-z0-9_]+|ghp_[A-Za-z0-9]+|AKIA[0-9A-Z]{16}' \
  -- ':(exclude)Scripts/check-public-repo-safety.sh' || true)
if [ -n "$private_markers" ]; then
  printf '%s\n' "$private_markers" >&2
  report "tracked files contain a possible private key or access token"
fi

if [ "$failed" -ne 0 ]; then
  exit 1
fi

echo "Public repository safety check passed."
