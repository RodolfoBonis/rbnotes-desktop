import 'dart:convert';

import 'package:equatable/equatable.dart';

/// Enriquecimento por IA de uma nota, espelhando o JSON `NoteAi` do
/// `docs/backend-contract.md`. Persistido em `note_ai.json`.
class NoteAi extends Equatable {
  const NoteAi({
    required this.title,
    required this.tldr,
    required this.points,
    required this.actions,
    required this.decisions,
    required this.questions,
    required this.speakerNames,
    this.quote,
  });

  factory NoteAi.fromJson(Map<String, dynamic> j) => NoteAi(
    title: (j['title'] as String?) ?? '',
    tldr: (j['tldr'] as String?) ?? '',
    points: _stringList(j['points']),
    quote: j['quote'] == null
        ? null
        : NoteQuote.fromJson((j['quote'] as Map).cast<String, dynamic>()),
    actions: ((j['actions'] as List?) ?? const [])
        .map((e) => NoteAction.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
    decisions: _stringList(j['decisions']),
    questions: _stringList(j['questions']),
    speakerNames: j['speakerNames'] == null
        ? const SpeakerNames(others: [], segments: [])
        : SpeakerNames.fromJson(
            (j['speakerNames'] as Map).cast<String, dynamic>(),
          ),
  );

  factory NoteAi.decode(String raw) =>
      NoteAi.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());

  final String title;
  final String tldr;
  final List<String> points;
  final NoteQuote? quote;
  final List<NoteAction> actions;
  final List<String> decisions;
  final List<String> questions;
  final SpeakerNames speakerNames;

  Map<String, dynamic> toJson() => {
    'title': title,
    'tldr': tldr,
    'points': points,
    if (quote != null) 'quote': quote!.toJson(),
    'actions': actions.map((a) => a.toJson()).toList(),
    'decisions': decisions,
    'questions': questions,
    'speakerNames': speakerNames.toJson(),
  };

  String encode() => jsonEncode(toJson());

  static List<String> _stringList(Object? v) =>
      ((v as List?) ?? const []).map((e) => e.toString()).toList();

  @override
  List<Object?> get props => [
    title,
    tldr,
    points,
    quote,
    actions,
    decisions,
    questions,
    speakerNames,
  ];
}

/// Citação em destaque com o instante do áudio (`atMs`).
class NoteQuote extends Equatable {
  const NoteQuote({
    required this.segmentIndex,
    required this.text,
    required this.speaker,
    required this.atMs,
  });

  factory NoteQuote.fromJson(Map<String, dynamic> j) => NoteQuote(
    segmentIndex: (j['segmentIndex'] as num?)?.toInt() ?? 0,
    text: (j['text'] as String?) ?? '',
    speaker: (j['speaker'] as String?) ?? '',
    atMs: (j['atMs'] as num?)?.toInt() ?? 0,
  );

  final int segmentIndex;
  final String text;
  final String speaker;
  final int atMs;

  Map<String, dynamic> toJson() => {
    'segmentIndex': segmentIndex,
    'text': text,
    'speaker': speaker,
    'atMs': atMs,
  };

  @override
  List<Object?> get props => [segmentIndex, text, speaker, atMs];
}

/// Uma ação extraída (texto, responsável e prazo opcional).
class NoteAction extends Equatable {
  const NoteAction({required this.text, this.owner, this.due});

  factory NoteAction.fromJson(Map<String, dynamic> j) => NoteAction(
    text: (j['text'] as String?) ?? '',
    owner: j['owner'] as String?,
    due: j['due'] == null ? null : DateTime.tryParse(j['due'] as String),
  );

  final String text;
  final String? owner;
  final DateTime? due;

  Map<String, dynamic> toJson() => {
    'text': text,
    if (owner != null) 'owner': owner,
    if (due != null) 'due': due!.toIso8601String(),
  };

  @override
  List<Object?> get props => [text, owner, due];
}

/// Nomes inferidos dos falantes "outros" e a atribuição por segmento.
class SpeakerNames extends Equatable {
  const SpeakerNames({required this.others, required this.segments});

  factory SpeakerNames.fromJson(Map<String, dynamic> j) => SpeakerNames(
    others: ((j['others'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
    segments: ((j['segments'] as List?) ?? const [])
        .map((e) => SpeakerSegment.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
  );

  final List<String> others;
  final List<SpeakerSegment> segments;

  Map<String, dynamic> toJson() => {
    'others': others,
    'segments': segments.map((s) => s.toJson()).toList(),
  };

  @override
  List<Object?> get props => [others, segments];
}

class SpeakerSegment extends Equatable {
  const SpeakerSegment({
    required this.index,
    required this.speaker,
    required this.inferred,
  });

  factory SpeakerSegment.fromJson(Map<String, dynamic> j) => SpeakerSegment(
    index: (j['index'] as num?)?.toInt() ?? 0,
    speaker: (j['speaker'] as String?) ?? '',
    inferred: (j['inferred'] as bool?) ?? false,
  );

  final int index;
  final String speaker;
  final bool inferred;

  Map<String, dynamic> toJson() => {
    'index': index,
    'speaker': speaker,
    'inferred': inferred,
  };

  @override
  List<Object?> get props => [index, speaker, inferred];
}
