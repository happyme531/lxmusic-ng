import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxmusic_app/main.dart';

void main() {
  testWidgets('renders workbench shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LxMusicApp()));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('曲库'), findsAtLeastNWidgets(1));
    expect(find.text('工作台'), findsOneWidget);
    expect(find.text('预览'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
