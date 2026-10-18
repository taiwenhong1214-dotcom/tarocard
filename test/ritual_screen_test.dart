import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taro_card/main.dart';

void main() {
  testWidgets('ritual screen: entrance completes, pile visible, tap draws card', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      home: RitualScreen(
        topic: availableTopics.first,
        spread: availableSpreads.first,
        lang: AppLanguage.zh,
      ),
    ));

    await tester.pump();
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);

    final promptText = find.textContaining('抽取第 1');
    expect(promptText, findsOneWidget);
    final op = tester.widget<Opacity>(
      find.ancestor(of: promptText, matching: find.byType(Opacity)).first,
    );
    expect(op.opacity, greaterThan(0.9), reason: 'entrance animation stuck (opacity still 0)');

    expect(find.byType(GestureDetector), findsNWidgets(tarotDeck.length));

    final lastCard = find.byType(GestureDetector).last;
    await tester.tap(lastCard, warnIfMissed: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('抽取第 2'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('ritual screen works even when animations are muted (TickerMode off)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      home: TickerMode(
        enabled: false,
        child: RitualScreen(
          topic: availableTopics.first,
          spread: availableSpreads.first,
          lang: AppLanguage.zh,
        ),
      ),
    ));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();

    final promptText = find.textContaining('抽取第 1');
    expect(promptText, findsOneWidget);
    final op = tester.widget<Opacity>(
      find.ancestor(of: promptText, matching: find.byType(Opacity)).first,
    );
    expect(op.opacity, 1.0, reason: 'timer fallback should reveal content when tickers are muted');

    final firstCard = find.byType(GestureDetector).first;
    await tester.tap(firstCard, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('抽取第 2'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('every spread layout can be fully drawn by tapping the pile', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final spread in availableSpreads) {
      await tester.pumpWidget(MaterialApp(
        home: RitualScreen(
          topic: availableTopics.first,
          spread: spread,
          lang: AppLanguage.zh,
        ),
      ));
      await tester.pump();
      for (int f = 0; f < 7; f++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      final count = spread.positionsZh.length;
      for (var i = 0; i < count; i++) {
        await tester.tap(find.byType(GestureDetector).last, warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1200));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 900));

      expect(tester.takeException(), isNull, reason: '${spread.nameZh} threw during draw');
      expect(find.textContaining('开始解读'), findsOneWidget, reason: '${spread.nameZh} did not complete all ${count} draws');
    }
  });
}
