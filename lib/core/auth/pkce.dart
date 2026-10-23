import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Par PKCE (RFC 7636) + `state`/`nonce` de um fluxo Authorization Code.
///
/// Gerado por login; o `codeVerifier` fica só em memória (nunca persistido) e o
/// `codeChallenge` (S256) vai na URL de autorização.
class PkcePair {
  const PkcePair({
    required this.codeVerifier,
    required this.codeChallenge,
    required this.state,
    required this.nonce,
  });

  /// Gera um par novo com entropia de [random] (injetável em testes).
  factory PkcePair.generate([Random? random]) {
    final rng = random ?? Random.secure();
    final verifier = _randomUrlSafe(rng, 32);
    return PkcePair(
      codeVerifier: verifier,
      codeChallenge: challengeFor(verifier),
      state: _randomUrlSafe(rng, 16),
      nonce: _randomUrlSafe(rng, 16),
    );
  }

  final String codeVerifier;
  final String codeChallenge;
  final String state;
  final String nonce;

  /// `code_challenge` S256 de um `code_verifier` (base64url sem padding).
  static String challengeFor(String verifier) {
    final digest = sha256.convert(ascii.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  static String _randomUrlSafe(Random rng, int bytes) {
    final data = List<int>.generate(bytes, (_) => rng.nextInt(256));
    return base64UrlEncode(data).replaceAll('=', '');
  }
}
