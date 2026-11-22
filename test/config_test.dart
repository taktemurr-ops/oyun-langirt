import 'package:flutter_test/flutter_test.dart';
import 'package:oyun_langirt/oyun_langirt.dart';

void main() {
  test('33 dilde ad, slogan, anlatım ve eğitim var', () {
    expect(langirtConfig.gameId, 'oyun-langirt');
    expect(langirtConfig.title.length, 33);
    expect(langirtConfig.tagline.length, 33);
    for (final s in langirtConfig.tutorial) {
      expect(s.text.length, 33);
      expect(s.text.every((t) => t.trim().isNotEmpty), isTrue);
    }
  });
}
