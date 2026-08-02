#!/bin/sh

# Xcode Cloud runs this script after cloning the repository, before resolving
# packages and building. It sets the build number (CFBundleVersion) to Xcode
# Cloud's monotonically increasing build number ($CI_BUILD_NUMBER) so every
# uploaded build is unique and higher than the last — avoiding the
# "bundle version must be higher than the previously uploaded version" error.
#
# See: https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds

set -e

if [ -z "$CI_BUILD_NUMBER" ]; then
    echo "CI_BUILD_NUMBER is not set; leaving CURRENT_PROJECT_VERSION unchanged."
    exit 0
fi

PBXPROJ="$CI_PRIMARY_REPOSITORY_PATH/ECHO.xcodeproj/project.pbxproj"

# Update CURRENT_PROJECT_VERSION for every build configuration.
/usr/bin/sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9.]+;/CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER};/g" "$PBXPROJ"

echo "Set CURRENT_PROJECT_VERSION to ${CI_BUILD_NUMBER}."
