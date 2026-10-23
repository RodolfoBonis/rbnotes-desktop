/// Mascara dados sensíveis (CPF, telefone, cartão de crédito) no texto da
/// transcrição ANTES de enviá-lo à IA, conforme a preferência "Mascarar dados
/// sensíveis" (design v3 › Inteligência › Privacidade).
///
/// Local-first e conservador: só mascara o que casa com um formato claro, para
/// não corromper o texto. O áudio nunca sai do Mac; isto cuida do texto.
abstract final class PrivacyMasker {
  // CPF: 000.000.000-00 ou 00000000000 (11 dígitos isolados).
  static final _cpf = RegExp(
    r'(?<!\d)(\d{3}\.\d{3}\.\d{3}-\d{2}|\d{11})(?!\d)',
  );

  // Cartão: 16 dígitos, com ou sem separadores (espaço/hífen).
  static final _card = RegExp(
    r'(?<!\d)(?:\d[ -]?){15}\d(?!\d)',
  );

  // Telefone BR: (11) 99999-9999, +55 11 99999 9999, 11999999999, etc.
  static final _phone = RegExp(
    r'(?<![\d])(?:\+?55[\s.-]?)?(?:\(?\d{2}\)?[\s.-]?)?\d{4,5}[\s.-]?\d{4}(?![\d])',
  );

  /// Substitui CPF, cartão e telefone por marcadores.
  ///
  /// A ordem importa: cartão (16) e CPF (11) antes do telefone, para não
  /// consumir parte de um número maior como telefone.
  static String mask(String input) {
    if (input.isEmpty) return input;
    var out = input.replaceAllMapped(_card, (m) {
      // Evita mascarar algo que, sem separadores, seja na verdade um CPF (11).
      final digits = m[0]!.replaceAll(RegExp(r'\D'), '');
      return digits.length == 16 ? '•••• cartão ••••' : m[0]!;
    });
    out = out.replaceAll(_cpf, '•••.•••.•••-•• (CPF)');
    out = out.replaceAllMapped(_phone, (m) {
      final digits = m[0]!.replaceAll(RegExp(r'\D'), '');
      // Telefone BR tem 10 (fixo) ou 11 (celular) dígitos; ignora o resto.
      if (digits.length < 10 || digits.length > 11) return m[0]!;
      return '(••) •••••-•••• (telefone)';
    });
    return out;
  }

  /// `true` se [input] contém algum dado sensível reconhecível.
  static bool hasSensitiveData(String input) => mask(input) != input;
}
