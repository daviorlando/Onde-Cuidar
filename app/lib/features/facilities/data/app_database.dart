import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// Snapshots completos e validados do catálogo. Apenas um fica ativo; o anterior
/// é mantido para diagnóstico e nunca é apagado antes de o novo ser ativado.
class CatalogSnapshots extends Table {
  TextColumn get version => text()();
  IntColumn get schemaVersion => integer()();
  TextColumn get sha256 => text()();
  TextColumn get payload => text()();

  /// `embedded` (APK) ou `remote` (sincronização).
  TextColumn get origin => text()();
  DateTimeColumn get importedAt => dateTime()();
  BoolColumn get active => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {version};
}

/// Linha única (id = 1) com o estado da sincronização do catálogo.
class SyncStates extends Table {
  IntColumn get id => integer()();
  TextColumn get etag => text().nullable()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  DateTimeColumn get lastSuccessAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
  IntColumn get consecutiveFailures =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Preferências locais; sobrevivem à substituição do catálogo.
class Preferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class StoredCatalog {
  const StoredCatalog({
    required this.version,
    required this.sha256,
    required this.payload,
    required this.origin,
    required this.importedAt,
  });

  final String version;
  final String sha256;
  final String payload;
  final String origin;
  final DateTime importedAt;
}

@DriftDatabase(tables: [CatalogSnapshots, SyncStates, Preferences])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Versão do esquema do banco — diferente da versão do catálogo.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await into(syncStates)
          .insert(SyncStatesCompanion.insert(id: const Value(1)));
    },
  );

  Future<StoredCatalog?> activeCatalog() async {
    final row =
        await (select(catalogSnapshots)
              ..where((t) => t.active.equals(true))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return StoredCatalog(
      version: row.version,
      sha256: row.sha256,
      payload: row.payload,
      origin: row.origin,
      importedAt: row.importedAt,
    );
  }

  /// Grava e ativa um snapshot já validado, numa única transação.
  /// Em falha, a transação é desfeita e o snapshot anterior continua ativo.
  Future<void> activateSnapshot({
    required String version,
    required int schemaVersion,
    required String sha256,
    required String payload,
    required String origin,
    required DateTime importedAt,
  }) => transaction(() async {
    final previous = await activeCatalog();
    await into(catalogSnapshots).insertOnConflictUpdate(
      CatalogSnapshotsCompanion.insert(
        version: version,
        schemaVersion: schemaVersion,
        sha256: sha256,
        payload: payload,
        origin: origin,
        importedAt: importedAt,
        active: const Value(false),
      ),
    );
    await update(catalogSnapshots)
        .write(const CatalogSnapshotsCompanion(active: Value(false)));
    await (update(catalogSnapshots)..where((t) => t.version.equals(version)))
        .write(const CatalogSnapshotsCompanion(active: Value(true)));
    // Mantém apenas o ativo e o imediatamente anterior.
    await (delete(
      catalogSnapshots,
    )..where((t) => t.version.isNotIn([version, ?previous?.version]))).go();
  });

  Future<SyncState> syncState() =>
      (select(syncStates)..where((t) => t.id.equals(1))).getSingle();

  Future<void> updateSyncState(SyncStatesCompanion data) =>
      (update(syncStates)..where((t) => t.id.equals(1))).write(data);

  Future<String?> preference(String key) async => (await (select(
    preferences,
  )..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setPreference(String key, String value) => into(
    preferences,
  ).insertOnConflictUpdate(PreferencesCompanion.insert(key: key, value: value));
}
