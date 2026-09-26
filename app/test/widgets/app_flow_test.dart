import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:onde_cuidar/app/app.dart';
import 'package:onde_cuidar/app/providers.dart';
import 'package:onde_cuidar/features/facilities/data/app_database.dart';
import 'package:onde_cuidar/features/facilities/data/catalog_repository.dart';
import 'package:onde_cuidar/features/offline/data/road_package_repository.dart';
import 'package:onde_cuidar/features/search/presentation/filters_sheet.dart';

import '../features/offline/road_package_test.dart' show bundle;
import '../support/fixtures.dart';

/// Catálogo sintético com casos de filtro: pública SUS 24h, privada sem telefone.
String widgetCatalog() {
  final json = catalogJson(version: '2026-01-01.1', count: 2);
  final facilities = json['facilities']! as List;
  (facilities[0] as Map)
    ..['name'] = 'UNIDADE SINTÉTICA PÚBLICA'
    ..['is_24h'] = 'yes'
    ..['phone'] = '8738000000';
  (facilities[1] as Map)
    ..['name'] = 'CLÍNICA SINTÉTICA PRIVADA'
    ..['administrative_nature'] = 'private'
    ..['sus_access'] = 'no';
  return jsonEncode(json);
}

/// Alterna E/S real (arquivos, SQLite) e quadros do relógio falso do teste.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  late Directory dir;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('widget');
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    // Tela de telefone típico: 411 × 914 dp.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final graph = encodeGraph(
      [(-9.4, -40.5), (-9.4, -40.49)],
      [(0, 1), (1, 0)],
    );
    final assets = bundle(graph);
    final catalog = widgetCatalog();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          httpClientProvider.overrideWithValue(
            MockClient((_) async => http.Response('sem rede no teste', 599)),
          ),
          catalogRepositoryProvider.overrideWithValue(
            CatalogRepository(db, (_) async => catalog),
          ),
          roadPackageRepositoryProvider.overrideWithValue(
            RoadPackageRepository(
              directory: dir,
              loadAsset: (k) async => Uint8List.fromList(assets[k]!),
            ),
          ),
        ],
        child: const OndeCuidarApp(),
      ),
    );
    await settle(tester);
  }

  testWidgets(
    'T01/RF06: lista o catálogo local sem rede, em ordem alfabética',
    (tester) async {
      await pumpApp(tester);
      expect(find.text('2 unidades compatíveis'), findsOneWidget);
      expect(find.textContaining('Ordem alfabética'), findsOneWidget);
      final clinic = tester.getTopLeft(find.text('CLÍNICA SINTÉTICA PRIVADA'));
      final unit = tester.getTopLeft(find.text('UNIDADE SINTÉTICA PÚBLICA'));
      expect(clinic.dy, lessThan(unit.dy));
      expect(find.textContaining('Baixe o mapa da região'), findsOneWidget);
    },
  );

  testWidgets('busca textual ignora acentos', (tester) async {
    await pumpApp(tester);
    await tester.enterText(find.byType(TextField), 'clinica');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('1 unidade compatível'), findsOneWidget);
    expect(find.text('UNIDADE SINTÉTICA PÚBLICA'), findsNothing);
  });

  testWidgets(
    'T02/CT06: combinação sem resultados preserva filtros e explica',
    (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Filtros'));
      await tester.pumpAndSettle();
      final sheetList = find
          .descendant(
            of: find.byType(FiltersSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.widgetWithText(FilterChip, '24 horas'),
        200,
        scrollable: sheetList,
      );
      await tester.tap(find.widgetWithText(FilterChip, 'Privada'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterChip, '24 horas'));
      await tester.pump();
      expect(find.text('Aplicar (nenhum resultado)'), findsOneWidget);
      await tester.tap(find.text('Aplicar (nenhum resultado)'));
      await tester.pumpAndSettle();
      expect(
        find.text('Nenhuma unidade atende a todas as condições escolhidas.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(InputChip, 'Privada'), findsOneWidget);
      expect(find.widgetWithText(InputChip, '24 horas'), findsOneWidget);
      expect(
        find.textContaining('Sem o filtro "24 horas": 1 unidade(s)'),
        findsOneWidget,
      );

      await tester.tap(find.text('Limpar filtros'));
      await tester.pumpAndSettle();
      expect(find.text('2 unidades compatíveis'), findsOneWidget);
    },
  );

  testWidgets('teclado não volta ao fechar filtros (achado no S20 FE)', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.text('Filtros'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Ver 2 resultados'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('T04: campos desconhecidos aparecem como "Não informado"', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('CLÍNICA SINTÉTICA PRIVADA'));
    await tester.pumpAndSettle();
    expect(find.text('Não informado'), findsWidgets);
    expect(
      find.textContaining('não confirmados pela curadoria'),
      findsOneWidget,
    );
    expect(find.text('Sem atendimento SUS no cadastro'), findsOneWidget);
    expect(find.textContaining('Ligar'), findsNothing);
  });

  testWidgets('T07: instala o mapa da região a partir do pacote do app', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Dados e mapas offline'));
    await tester.pumpAndSettle();
    final page = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.textContaining('Instalar mapa da região'),
      200,
      scrollable: page,
    );
    expect(find.text('Mapa não instalado.'), findsOneWidget);
    await tester.tap(find.textContaining('Instalar mapa da região'));
    await settle(tester);
    await tester.scrollUntilVisible(
      find.text('Mapa instalado e verificado.'),
      -200,
      scrollable: page,
    );
    expect(find.text('Mapa instalado e verificado.'), findsOneWidget);
  });

  testWidgets('RNF05: alvos de toque de pelo menos 48 dp e rótulos', (
    tester,
  ) async {
    await pumpApp(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });

  testWidgets('RNF05: contraste também no tema escuro (achado no S20 FE)', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpApp(tester);
    // Tela inicial com o banner do mapa (cartão tonal).
    expect(find.textContaining('Baixe o mapa da região'), findsOneWidget);
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    // Detalhe com o aviso de dados não confirmados.
    await tester.tap(find.text('CLÍNICA SINTÉTICA PRIVADA'));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });

  testWidgets('RNF05: texto a 200% sem overflow na tela inicial', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Onde Cuidar'), findsOneWidget);
  });
}
