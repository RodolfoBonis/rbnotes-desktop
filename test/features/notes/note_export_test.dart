import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/domain/note_ai.dart';
import 'package:rbnotes/features/notes/domain/note_export.dart';

void main() {
  final note = NoteRow(
    id: 'a',
    title: 'Planejamento',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    durationMs: 0,
    status: NoteStatus.ready,
    pinned: false,
    source: NoteSource.recording,
    favorite: false,
    kind: NoteKind.note,
    autoTitle: false,
    aiStatus: AiStatus.none,
    locked: false,
    deleted: false,
  );
  const segments = [
    SegmentRow(
      id: 1,
      noteId: 'a',
      speaker: SegmentSpeaker.me,
      startMs: 0,
      endMs: 1000,
      content: 'oi',
    ),
    SegmentRow(
      id: 2,
      noteId: 'a',
      speaker: SegmentSpeaker.others,
      startMs: 65000,
      endMs: 66000,
      content: 'olá',
    ),
  ];

  test('formatTimestamp em mm:ss', () {
    expect(formatTimestamp(65000), '01:05');
  });

  test('transcriptPlainText rotula falante e tempo', () {
    final text = transcriptPlainText(segments);
    expect(text, contains('[00:00] Eu: oi'));
    expect(text, contains('[01:05] Outros: olá'));
  });

  test('markdown inclui título e segmentos', () {
    final md = noteMarkdown(note, segments, const []);
    expect(md, startsWith('# Planejamento'));
    expect(md, contains('**Eu:**'));
  });

  test('txt inclui título e transcrição', () {
    final txt = noteTxt(note, segments);
    expect(txt, startsWith('Planejamento'));
    expect(txt, contains('Outros: olá'));
  });

  test('summaryMarkdown inclui tldr, pontos, decisões e ações', () {
    const ai = NoteAi(
      title: 'Planejamento',
      tldr: 'Resumo curto do encontro.',
      points: ['Ponto um', 'Ponto dois'],
      actions: [NoteAction(text: 'Enviar proposta', owner: 'Você')],
      decisions: ['Lançar só no iOS'],
      questions: [],
      speakerNames: SpeakerNames(others: [], segments: []),
    );
    final md = summaryMarkdown(note, ai);
    expect(md, startsWith('# Planejamento'));
    expect(md, contains('Resumo curto do encontro.'));
    expect(md, contains('## Pontos principais'));
    expect(md, contains('- Ponto um'));
    expect(md, contains('## Decisões'));
    expect(md, contains('## Ações'));
    expect(md, contains('- [ ] Enviar proposta — Você'));
  });

  test('summaryMarkdown sem ai avisa que o resumo não foi gerado', () {
    expect(summaryMarkdown(note, null), contains('Resumo ainda não gerado'));
  });

  test('buildZip gera um arquivo .zip válido com as entradas', () {
    final bytes = buildZip([
      (name: 'resumo.md', bytes: [0x23, 0x20, 0x4f, 0x69]),
      (name: 'audio.m4a', bytes: List<int>.filled(16, 0x41)),
    ]);
    // Assinatura do local file header (PK\x03\x04).
    expect(bytes.sublist(0, 4), [0x50, 0x4b, 0x03, 0x04]);
    // End of central directory record no fim (PK\x05\x06).
    final eocd = bytes.sublist(bytes.length - 22, bytes.length - 18);
    expect(eocd, [0x50, 0x4b, 0x05, 0x06]);
    // Os nomes das entradas aparecem nos headers.
    final text = String.fromCharCodes(bytes);
    expect(text.contains('resumo.md'), isTrue);
    expect(text.contains('audio.m4a'), isTrue);
  });
}
