/// Fachada do contrato nativo para o app.
///
/// Reexporta a API pública do plugin `rbnotes_native` (ver
/// `docs/native-contract.md`). Todo o app importa este arquivo, então quando o
/// plugin existe/compila basta esta reexportacao, e nenhuma feature muda.
/// Em testes, `FakeRbNative` implementa a mesma interface `RbNative`.
library;

export 'package:rbnotes_native/rbnotes_native.dart';
