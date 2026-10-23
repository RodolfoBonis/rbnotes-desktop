import 'dart:convert';

import 'package:equatable/equatable.dart';

/// Regra estruturada de uma coleção inteligente, avaliada localmente.
///
/// Espelha `POST /ai/collections/rule`
/// (`{keywords, folders?, minSpeakers?, openActions?}`). A UI mostra o
/// [CollectionRuleResult.ruleText]; a seleção de notas usa [matches].
class CollectionRule extends Equatable {
  const CollectionRule({
    this.keywords = const [],
    this.folders,
    this.minSpeakers,
    this.openActions,
  });

  factory CollectionRule.fromJson(Map<String, dynamic> j) => CollectionRule(
    keywords: ((j['keywords'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
    folders: (j['folders'] as List?)?.map((e) => e.toString()).toList(),
    minSpeakers: (j['minSpeakers'] as num?)?.toInt(),
    openActions: j['openActions'] as bool?,
  );

  factory CollectionRule.decode(String raw) =>
      CollectionRule.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());

  final List<String> keywords;
  final List<String>? folders;
  final int? minSpeakers;
  final bool? openActions;

  Map<String, dynamic> toJson() => {
    'keywords': keywords,
    if (folders != null) 'folders': folders,
    if (minSpeakers != null) 'minSpeakers': minSpeakers,
    if (openActions != null) 'openActions': openActions,
  };

  String encode() => jsonEncode(toJson());

  /// Avalia a regra contra uma nota candidata. Semântica (AND entre critérios):
  /// a nota precisa satisfazer todos os critérios presentes na regra.
  bool matches(CollectionCandidate note) {
    if (folders != null && folders!.isNotEmpty) {
      if (note.folderId == null || !folders!.contains(note.folderId)) {
        return false;
      }
    }
    if (minSpeakers != null && note.speakerCount < minSpeakers!) return false;
    if (openActions == true && !note.hasOpenActions) return false;
    if (keywords.isNotEmpty) {
      final hay = _normalize(note.searchableText);
      final hit = keywords.any((k) => hay.contains(_normalize(k)));
      if (!hit) return false;
    }
    return true;
  }

  static String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[àáâãäå]'), 'a')
      .replaceAll(RegExp('[èéêë]'), 'e')
      .replaceAll(RegExp('[ìíîï]'), 'i')
      .replaceAll(RegExp('[òóôõö]'), 'o')
      .replaceAll(RegExp('[ùúûü]'), 'u')
      .replaceAll('ç', 'c');

  @override
  List<Object?> get props => [keywords, folders, minSpeakers, openActions];
}

/// Nota candidata à avaliação de uma coleção.
class CollectionCandidate {
  const CollectionCandidate({
    required this.folderId,
    required this.speakerCount,
    required this.hasOpenActions,
    required this.searchableText,
  });

  final String? folderId;
  final int speakerCount;
  final bool hasOpenActions;

  /// Título + resumo + falantes + transcrição concatenados.
  final String searchableText;
}

/// Resultado de "criar coleção": rótulo, texto humano e regra estruturada.
class CollectionRuleResult extends Equatable {
  const CollectionRuleResult({
    required this.label,
    required this.ruleText,
    required this.rule,
  });

  /// Gera uma regra localmente a partir da descrição em linguagem natural
  /// (fallback offline; espelha `createColl()` do design v3). Remove stopwords
  /// e usa palavras com 5+ letras como palavras-chave.
  factory CollectionRuleResult.fromDescription(String description) {
    final q = description.trim();
    final label = q.isEmpty ? 'Coleção' : q[0].toUpperCase() + q.substring(1);
    const stop = {
      'sobre',
      'tudo',
      'todas',
      'todos',
      'notas',
      'minhas',
      'coisas',
      'relacionadas',
      'qualquer',
      'quando',
      'conversas',
      'para',
      'com',
    };
    final normalized = CollectionRule._normalize(q);
    final keywords = normalized
        .split(RegExp('[^a-z0-9]+'))
        .where((w) => w.length >= 5 && !stop.contains(w))
        .toSet()
        .take(3)
        .toList();
    final ruleText = keywords.isNotEmpty
        ? 'Notas que mencionam ${keywords.join(', ')}'
        : q;
    return CollectionRuleResult(
      label: label.length > 26 ? '${label.substring(0, 25)}…' : label,
      ruleText: ruleText,
      rule: CollectionRule(keywords: keywords),
    );
  }

  final String label;
  final String ruleText;
  final CollectionRule rule;

  @override
  List<Object?> get props => [label, ruleText, rule];
}
