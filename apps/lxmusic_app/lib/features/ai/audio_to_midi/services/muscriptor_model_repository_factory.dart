import 'muscriptor_model_repository.dart';
import 'muscriptor_model_repository_stub.dart'
    if (dart.library.io) 'muscriptor_model_repository_io.dart'
    as platform;

MuscriptorModelRepository createDefaultMuscriptorModelRepository() =>
    platform.createMuscriptorModelRepository();
