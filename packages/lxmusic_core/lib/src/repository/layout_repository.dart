import '../domain/game_profile.dart';

abstract class LayoutRepository {
  KeyLayout load(String id);
  List<KeyLayout> list();
}
