import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/auth/pkce.dart';

void main() {
  group('PKCE', () {
    test('challenge S256 bate com o vetor da RFC 7636', () {
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      const expected = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';
      expect(PkcePair.challengeFor(verifier), expected);
    });

    test('generate produz verifier/challenge/state/nonce válidos', () {
      final pair = PkcePair.generate(Random(42));
      // Verifier base64url sem padding, dentro de 43..128 chars (RFC).
      expect(pair.codeVerifier.length, inInclusiveRange(43, 128));
      expect(pair.codeVerifier, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(pair.codeChallenge, PkcePair.challengeFor(pair.codeVerifier));
      expect(pair.state, isNotEmpty);
      expect(pair.nonce, isNotEmpty);
      expect(pair.state, isNot(pair.nonce));
    });

    test('pares distintos têm verifiers distintos', () {
      final a = PkcePair.generate();
      final b = PkcePair.generate();
      expect(a.codeVerifier, isNot(b.codeVerifier));
      expect(a.state, isNot(b.state));
    });
  });
}
