#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

flutter pub get
dart analyze

pushd packages/lxmusic_core >/dev/null
dart test
popd >/dev/null

pushd apps/lxmusic_app >/dev/null
flutter analyze
flutter test
popd >/dev/null
