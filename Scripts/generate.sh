#!/bin/bash
# Regenerates ChettaCash.xcodeproj from project.yml.
#
# XcodeGen cannot declare SPM test targets in a scheme's test action, so the
# DomainTests and DataTests schemes are maintained by hand in Schemes/ and copied
# back in afterwards — generation wipes anything already in the project bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
mkdir -p ChettaCash.xcodeproj/xcshareddata/xcschemes
cp Schemes/*.xcscheme ChettaCash.xcodeproj/xcshareddata/xcschemes/
echo "Restored hand-written schemes: $(ls Schemes | tr '\n' ' ')"
