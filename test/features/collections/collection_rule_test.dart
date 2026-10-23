import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/collections/domain/collection_rule.dart';

CollectionCandidate _note({
  String? folder,
  int speakers = 1,
  bool openActions = false,
  String text = '',
}) => CollectionCandidate(
  folderId: folder,
  speakerCount: speakers,
  hasOpenActions: openActions,
  searchableText: text,
);

void main() {
  group('CollectionRule.matches', () {
    test('keyword match is accent/case-insensitive', () {
      const rule = CollectionRule(keywords: ['financas']);
      expect(
        rule.matches(_note(text: 'App de Finanças pessoais')),
        isTrue,
      );
      expect(rule.matches(_note(text: 'Lista do mercado')), isFalse);
    });

    test('minSpeakers filters meetings', () {
      const rule = CollectionRule(minSpeakers: 2);
      expect(rule.matches(_note(speakers: 3)), isTrue);
      expect(rule.matches(_note(speakers: 1)), isFalse);
    });

    test('folders restricts to a folder', () {
      const rule = CollectionRule(folders: ['ideias']);
      expect(rule.matches(_note(folder: 'ideias')), isTrue);
      expect(rule.matches(_note(folder: 'trabalho')), isFalse);
    });

    test('openActions requires an open action', () {
      const rule = CollectionRule(openActions: true);
      expect(rule.matches(_note(openActions: true)), isTrue);
      expect(rule.matches(_note(openActions: false)), isFalse);
    });

    test('criteria combine with AND', () {
      const rule = CollectionRule(
        keywords: ['podcast'],
        folders: ['ideias'],
        openActions: true,
      );
      expect(
        rule.matches(
          _note(folder: 'ideias', openActions: true, text: 'ideia de podcast'),
        ),
        isTrue,
      );
      expect(
        rule.matches(
          _note(folder: 'trabalho', openActions: true, text: 'podcast'),
        ),
        isFalse,
      );
    });

    test('round-trips through JSON', () {
      const rule = CollectionRule(
        keywords: ['x', 'y'],
        folders: ['a'],
        minSpeakers: 2,
        openActions: true,
      );
      expect(CollectionRule.decode(rule.encode()), rule);
    });
  });

  group('CollectionRuleResult.fromDescription', () {
    test('extracts keywords and drops stopwords/short words', () {
      final r = CollectionRuleResult.fromDescription(
        'tudo sobre o app de finanças',
      );
      expect(r.rule.keywords, contains('financas'));
      expect(r.rule.keywords, isNot(contains('sobre')));
      expect(r.ruleText, startsWith('Notas que mencionam'));
      expect(r.label, startsWith('Tudo sobre'));
    });

    test('truncates a long label', () {
      final r = CollectionRuleResult.fromDescription(
        'conversas muito longas sobre planejamento estratégico anual detalhado',
      );
      expect(r.label.length, lessThanOrEqualTo(26));
      expect(r.label, endsWith('…'));
    });
  });
}
