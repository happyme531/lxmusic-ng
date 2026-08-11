import 'archive_import_service.dart';
import 'archive_import_service_stub.dart'
    if (dart.library.io) 'archive_import_service_io.dart'
    as impl;

ArchiveImportService createArchiveImportService() =>
    impl.createArchiveImportService();
