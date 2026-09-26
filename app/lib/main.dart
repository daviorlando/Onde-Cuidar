import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'features/facilities/data/app_database.dart';
import 'features/facilities/data/catalog_repository.dart';
import 'features/offline/data/road_package_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  final db = AppDatabase(driftDatabase(name: 'onde_cuidar'));
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        catalogRepositoryProvider.overrideWithValue(
          CatalogRepository(db, rootBundle.loadString),
        ),
        roadPackageRepositoryProvider.overrideWithValue(
          RoadPackageRepository(
            directory: support,
            loadAsset: (key) async =>
                (await rootBundle.load(key)).buffer.asUint8List(),
          ),
        ),
      ],
      child: const OndeCuidarApp(),
    ),
  );
}
