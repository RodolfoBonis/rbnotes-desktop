import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/ai_activity.dart';
import 'package:rbnotes/features/notes/domain/note_summary_status.dart';

void main() {
  SummaryStatus run({
    NoteStatus note = NoteStatus.ready,
    AiStatus ai = AiStatus.none,
    String? folder,
    bool skipPersonal = false,
    AiPhase phase = AiPhase.idle,
  }) => computeSummaryStatus(
    noteStatus: note,
    aiStatus: ai,
    folderId: folder,
    skipPersonal: skipPersonal,
    aiPhase: phase,
  );

  test('transcricao falha vence tudo', () {
    expect(
      run(note: NoteStatus.failed, ai: AiStatus.ready).kind,
      SummaryStatusKind.transcriptionFailed,
    );
  });

  test('transcrevendo enquanto a nota ainda roda', () {
    expect(
      run(note: NoteStatus.transcribing).kind,
      SummaryStatusKind.transcribing,
    );
    expect(
      run(note: NoteStatus.recording).kind,
      SummaryStatusKind.transcribing,
    );
  });

  test('ai ready mostra o resumo', () {
    final s = run(ai: AiStatus.ready);
    expect(s.kind, SummaryStatusKind.ready);
    expect(s.showsSummary, isTrue);
  });

  test('ai failed pede nova tentativa', () {
    expect(run(ai: AiStatus.failed).kind, SummaryStatusKind.summaryFailed);
  });

  test('none na pasta Pessoal com privacidade = disabledPersonal', () {
    expect(
      run(folder: 'pessoal', skipPersonal: true).kind,
      SummaryStatusKind.disabledPersonal,
    );
  });

  test('none fora da Pessoal = desativado generico', () {
    expect(
      run(folder: 'trabalho', skipPersonal: true).kind,
      SummaryStatusKind.disabled,
    );
    expect(
      run(folder: 'pessoal').kind,
      SummaryStatusKind.disabled,
    );
  });

  test('pending traz o status real do SSE no detail', () {
    expect(
      run(ai: AiStatus.pending, phase: AiPhase.queued).detail,
      'Na fila…',
    );
    expect(
      run(ai: AiStatus.pending, phase: AiPhase.dailyLimit).detail,
      contains('Limite'),
    );
    expect(
      run(ai: AiStatus.pending, phase: AiPhase.streaming).detail,
      contains('Gerando'),
    );
  });
}
