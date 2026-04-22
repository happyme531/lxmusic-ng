import 'package:flutter_riverpod/flutter_riverpod.dart';

final librarySelectionProvider =
    NotifierProvider<LibrarySelectionNotifier, Set<String>>(
  LibrarySelectionNotifier.new,
);

final isLibrarySelectionModeProvider = Provider<bool>((ref) {
  return ref.watch(librarySelectionProvider).isNotEmpty;
});

class LibrarySelectionNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  void startWith(String fileName) {
    state = <String>{fileName};
  }

  void toggle(String fileName) {
    final next = <String>{...state};
    if (!next.add(fileName)) {
      next.remove(fileName);
    }
    state = next;
  }

  void selectAll(Iterable<String> fileNames) {
    state = fileNames.toSet();
  }

  void invert(Iterable<String> fileNames) {
    final scope = fileNames.toSet();
    state = scope.where((fileName) => !state.contains(fileName)).toSet();
  }

  void clear() {
    state = <String>{};
  }
}
