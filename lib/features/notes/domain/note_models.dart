import 'dart:convert';

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

/// Uma palavra transcrita com tempo e confiança (0..1).
class TranscriptWord extends Equatable {
  const TranscriptWord({
    required this.text,
    required this.startMs,
    required this.endMs,
    required this.probability,
  });

  factory TranscriptWord.fromJson(Map<String, dynamic> j) => TranscriptWord(
    text: j['text'] as String,
    startMs: (j['startMs'] as num).toInt(),
    endMs: (j['endMs'] as num).toInt(),
    probability: (j['prob'] as num).toDouble(),
  );

  final String text;
  final int startMs;
  final int endMs;
  final double probability;

  Map<String, dynamic> toJson() => {
    'text': text,
    'startMs': startMs,
    'endMs': endMs,
    'prob': probability,
  };

  @override
  List<Object?> get props => [text, startMs, endMs, probability];

  static String? encode(List<TranscriptWord>? words) =>
      (words == null || words.isEmpty)
      ? null
      : jsonEncode(words.map((w) => w.toJson()).toList());

  static List<TranscriptWord> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return (jsonDecode(raw) as List)
        .map((e) => TranscriptWord.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }
}

/// Segmento a persistir (ainda sem id), vindo da transcrição.
class DraftSegment extends Equatable {
  const DraftSegment({
    required this.speaker,
    required this.startMs,
    required this.endMs,
    required this.content,
    this.wordsJson,
  });

  final SegmentSpeaker speaker;
  final int startMs;
  final int endMs;
  final String content;

  /// Palavras com confiança, serializadas (ver [TranscriptWord]).
  final String? wordsJson;

  @override
  List<Object?> get props => [speaker, startMs, endMs, content, wordsJson];
}

/// Rótulo de exibição da tag (emoji + nome).
extension TagRowLabel on TagRow {
  String get displayLabel => emoji == null ? name : '$emoji $name';
}
