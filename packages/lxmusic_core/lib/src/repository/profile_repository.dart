import '../domain/game_profile.dart';

abstract class GameProfileRepository {
  GameProfile load(String id);
  List<GameProfile> list();
}
