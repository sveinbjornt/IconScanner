#!/bin/sh

xcodebuild  -parallelizeTargets \
            -project "IconScanner.xcodeproj" \
            -target "IconScanner" \
            -configuration "Release" \
            clean \
            build

open build/Release
