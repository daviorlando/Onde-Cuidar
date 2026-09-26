// Jornada completa no Android, pensada para rodar com a rede do aparelho
// desligada (CT01/CT09/CT10):
//   adb shell cmd connectivity airplane-mode enable
//   flutter test integration_test/offline_journey_test.dart
// Origem escolhida manualmente no mapa: nenhum dado de localização pessoal.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:onde_cuidar/features/routing/presentation/road_map_view.dart';
import 'package:onde_cuidar/main.dart' as app;

Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Não apareceu a tempo: $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('catálogo, mapa, origem manual e nova rota sem rede', (
    tester,
  ) async {
    final started = DateTime.now();
    await app.main();
    await waitFor(tester, find.textContaining('unidades compatíveis'));
    final firstList = DateTime.now().difference(started);
    debugPrint('MEDIDA primeira_lista_ms=${firstList.inMilliseconds}');

    // T07: instalar (ou confirmar) o pacote viário embarcado.
    await tester.tap(find.byTooltip('Dados e mapas offline'));
    await tester.pumpAndSettle();
    final install = find.textContaining('Instalar mapa da região');
    final installed = find.text('Mapa instalado e verificado.');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      if (install.evaluate().isNotEmpty || installed.evaluate().isNotEmpty) {
        break;
      }
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    if (install.evaluate().isNotEmpty) {
      await tester.ensureVisible(install);
      await tester.pumpAndSettle();
      await tester.tap(install);
    }
    await waitFor(tester, find.text('Mapa instalado e verificado.'));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // T05: origem manual no mapa (sem pedir permissão de localização).
    await tester.tap(find.text('Perto de mim'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Escolher ponto no mapa'));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(RoadMapView)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar este ponto'));
    await tester.pumpAndSettle();

    // T03: ordenação pela distância viária calculada no aparelho.
    final rankingStart = DateTime.now();
    await waitFor(
      tester,
      find.textContaining('Ordenado pela distância pelas ruas'),
    );
    await waitFor(tester, find.text('pelas ruas'));
    debugPrint(
      'MEDIDA ordenacao_viaria_ms=${DateTime.now().difference(rankingStart).inMilliseconds}',
    );

    // T04 → T06: rota inédita até a unidade mais próxima.
    await tester.tap(find.text('pelas ruas').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Traçar rota'));
    final routeStart = DateTime.now();
    await waitFor(
      tester,
      find.textContaining('calculada no aparelho, sem internet'),
    );
    debugPrint(
      'MEDIDA rota_ms=${DateTime.now().difference(routeStart).inMilliseconds}',
    );
    expect(find.byType(RoadMapView), findsOneWidget);
  });
}
