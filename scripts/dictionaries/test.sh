#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/dictionaries
swiftc -import-objc-header sources/Squirrel-Bridging-Header.h -I librime/src -I librime/include \
  sources/DictionaryStore.swift tests/dictionaries/DictionaryTests.swift lib/librime.1.dylib \
  -Xlinker -rpath -Xlinker "$PWD/lib" -o build/dictionaries/tests
build/dictionaries/tests
