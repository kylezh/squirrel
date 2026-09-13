#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
root="$PWD"
out="$root/build/spacing"
mkdir -p "$out"
sdk="$(xcrun --show-sdk-path)"
common=(-I librime/src -I librime/include -I "$sdk/System/Library/Frameworks/Tk.framework/Headers")
swiftc sources/InputSource.swift tests/spacing/InputSourceTests.swift -o "$out/input-source-tests"
"$out/input-source-tests"
swiftc sources/InputContinuityTracker.swift tests/spacing/TrackerTests.swift -o "$out/tracker-tests"
"$out/tracker-tests"
lua tests/spacing/LuaTests.lua
lua tests/spacing/EnglishLearningTests.lua
swiftc sources/InputContinuityTracker.swift sources/InputContextProbe.swift sources/SpacingContext.swift tests/spacing/TextClient.swift tests/spacing/NativeTests.swift -o "$out/native-tests"
"$out/native-tests"
swiftc sources/InputContinuityTracker.swift sources/InputContextProbe.swift sources/SpacingContext.swift sources/PeriodSequence.swift tests/spacing/TextClient.swift tests/spacing/PeriodTests.swift -o "$out/period-tests"
"$out/period-tests"
if [[ ! -f lib/librime.1.dylib || ! -f librime/src/rime_api_stdbool.h ]]; then
  echo 'Missing build dependencies: run git submodule update --init librime && bash action-install.sh' >&2
  exit 1
fi
mkdir -p "$out/test-data/lua"
cp tests/spacing/default.yaml tests/spacing/spacing_test*.yaml "$out/test-data/"
cp tests/spacing/direct_commit.lua config/spacing/lua/*.lua "$out/test-data/lua/"
DYLD_LIBRARY_PATH="$root/lib" bin/rime_deployer --build "$out/test-data" "$out/test-data"
swiftc -parse-as-library -import-objc-header sources/Squirrel-Bridging-Header.h "${common[@]}" sources/BridgingFunctions.swift sources/PeriodSequence.swift sources/InputContinuityTracker.swift sources/InputContextProbe.swift sources/SpacingContext.swift tests/spacing/TextClient.swift tests/spacing/EngineTests.swift lib/librime.1.dylib -Xlinker -rpath -Xlinker "$root/lib" -o "$out/engine-tests"
"$out/engine-tests" "$root"

# This database belongs only to the synthetic fixture; start the learning test fresh.
rm -rf "$out/test-data/spacing_test_english.userdb"
cc -I librime/src tests/spacing/EnglishLearningIntegration.c -o "$out/english-learning-tests"
"$out/english-learning-tests" "$root" train "$out/test-data"
"$out/english-learning-tests" "$root" verify "$out/test-data"
