#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT"
dart run tools/generate_yaml_assets.dart
dart analyze

cd "$ROOT/packages/lxmusic_core"
dart test

cd "$ROOT/apps/lxmusic_cli"
dart run bin/lxmusic_cli.dart validate-profiles >/dev/null

cd "$ROOT/apps/lxmusic_app"
flutter test
