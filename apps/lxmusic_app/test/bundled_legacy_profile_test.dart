import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_assets/lxmusic_assets.dart';
import 'package:lxmusic_core/lxmusic_core.dart';

void main() {
  test('bundled custom profiles preserve zero same-key intervals', () {
    final repository = YamlGameProfileRepository(bundledYamlAssetBundle);

    expect(repository.load('legacy_31').sameKeyMinIntervalMs, 0);
    expect(repository.load('legacy_32').sameKeyMinIntervalMs, 0);
  });
}
