import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/ai_activity.dart';

/// O que o cabeçalho da aba Resumo deve mostrar — estados honestos (bug 6).
///
/// Nunca mostramos "em preparação" sem um job real: `pending` só aparece
/// quando a nota está de fato com `aiStatus = pending` (marcado pelo
/// `EnrichmentService`).
enum SummaryStatusKind {
  /// Mostra o resumo real (`ai.tldr`, pontos, citação).
  ready,

  /// A transcrição ainda está rodando (ou a nota está gravando).
  transcribing,

  /// A transcrição falhou: "Não foi possível transcrever - Tentar de novo".
  transcriptionFailed,

  /// Resumo desligado pela regra de privacidade da pasta Pessoal.
  disabledPersonal,

  /// Resumo desligado por outra razão (auto-resumo off / sem fala).
  disabled,

  /// "Resumo em preparação…" com o status real vindo do SSE em detail.
  pending,

  /// O resumo falhou: "Não foi possível gerar o resumo - Tentar de novo".
  summaryFailed,
}

/// Estado derivado do Resumo + um detalhe opcional (para pending).
class SummaryStatus {
  const SummaryStatus(this.kind, {this.detail});

  final SummaryStatusKind kind;

  /// Texto secundário do estado pending (fila / limite diário / gerando),
  /// derivado da fase da IA (AiPhase) reportada pelo SSE.
  final String? detail;

  bool get showsSummary => kind == SummaryStatusKind.ready;
}

/// Deriva o estado honesto do Resumo a partir dos fatos (status da nota, status
/// da IA, pasta, privacidade e fase da IA). Função pura — fácil de testar.
SummaryStatus computeSummaryStatus({
  required NoteStatus noteStatus,
  required AiStatus aiStatus,
  required String? folderId,
  required bool skipPersonal,
  required AiPhase aiPhase,
}) {
  if (noteStatus == NoteStatus.failed) {
    return const SummaryStatus(SummaryStatusKind.transcriptionFailed);
  }
  if (noteStatus == NoteStatus.recording ||
      noteStatus == NoteStatus.transcribing) {
    return const SummaryStatus(SummaryStatusKind.transcribing);
  }
  // Nota transcrita (ready): o estado agora depende da IA.
  switch (aiStatus) {
    case AiStatus.ready:
      return const SummaryStatus(SummaryStatusKind.ready);
    case AiStatus.failed:
      return const SummaryStatus(SummaryStatusKind.summaryFailed);
    case AiStatus.pending:
      final detail = switch (aiPhase) {
        AiPhase.dailyLimit => 'Limite diário de resumos atingido',
        AiPhase.streaming => 'Gerando o resumo…',
        AiPhase.error => 'Tentando novamente…',
        AiPhase.queued || AiPhase.idle => 'Na fila…',
      };
      return SummaryStatus(SummaryStatusKind.pending, detail: detail);
    case AiStatus.none:
      if (skipPersonal && folderId == 'pessoal') {
        return const SummaryStatus(SummaryStatusKind.disabledPersonal);
      }
      return const SummaryStatus(SummaryStatusKind.disabled);
  }
}
