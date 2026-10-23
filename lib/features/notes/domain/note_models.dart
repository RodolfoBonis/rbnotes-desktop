import 'package:equatable/equatable.dart';
import 'package:rbnotes/data/database/database.dart';

/// Nota + tags, para a lista lateral.
class NoteListItem extends Equatable {
  const NoteListItem({required this.note, required this.tags});

  final NoteRow note;
  final List<TagRow> tags;

  @override
  List<Object?> get props => [note, tags];
}

/// Nota completa, para a tela de detalhe.
class NoteDetail extends Equatable {
  const NoteDetail({
    required this.note,
    required this.segments,
    required this.tags,
  });

  final NoteRow note;
  final List<SegmentRow> segments;
  final List<TagRow> tags;

  @override
  List<Object?> get props => [note, segments, tags];
}

/// Segmento a persistir (ainda sem id), vindo da transcrição.
class DraftSegment extends Equatable {
  const DraftSegment({
    required this.speaker,
    required this.startMs,
    required this.endMs,
    required this.content,
  });

  final SegmentSpeaker speaker;
  final int startMs;
  final int endMs;
  final String content;

  @override
  List<Object?> get props => [speaker, startMs, endMs, content];
}

/// Rótulo de exibição da tag (emoji + nome).
extension TagRowLabel on TagRow {
  String get displayLabel => emoji == null ? name : '$emoji $name';
}
