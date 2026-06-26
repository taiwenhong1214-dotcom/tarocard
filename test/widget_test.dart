import 'package:flutter_test/flutter_test.dart';
import 'package:taro_card/main.dart';

void main() {
  test('a newly pulled card can be recorded as unlocked', () {
    final engine = GachaEngine();
    final card = engine.pull();
    engine.ownedCards[card.nameZh] = 1;

    expect(engine.ownedCards.containsKey(card.nameZh), isTrue);
    expect(engine.ownedCards.length, 1);
  });

  test('free pull is unavailable on the same day', () {
    final engine = GachaEngine(lastFreePull: DateTime.now());
    expect(engine.canFreePull, isFalse);
  });
}
