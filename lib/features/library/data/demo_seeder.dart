// Arquivo de dados do design v3: strings longas são quebradas em literais
// adjacentes (concatenação) de propósito, para legibilidade.
// ignore_for_file: no_adjacent_strings_in_list
import 'package:drift/drift.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/domain/note_ai.dart';
import 'package:rbnotes/features/diary/data/diary_repository.dart';
import 'package:rbnotes/features/library/data/library_repository.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/domain/note_models.dart';
import 'package:uuid/uuid.dart';

/// Palavra com baixa confiança no design (o Whisper ouviu "Taís").
const _lowConfWord = 'Taís';

/// Uma ação do design (texto, responsável, concluída).
typedef _Act = ({String text, String owner, bool done});

/// Uma nota do design: tudo o que a UI mostra.
class _DemoNote {
  const _DemoNote({
    required this.id,
    required this.title,
    required this.folder,
    required this.ageDays,
    required this.hour,
    required this.minute,
    required this.durationSec,
    required this.speakers,
    required this.tldr,
    required this.points,
    required this.quoteIndex,
    required this.actions,
    required this.decisions,
    required this.questions,
    required this.transcript,
    this.favorite = false,
    this.diary = false,
  });

  final String id;
  final String title;
  final String folder;
  final int ageDays;
  final int hour;
  final int minute;
  final int durationSec;
  final bool favorite;
  final bool diary;
  final List<String> speakers;
  final String tldr;
  final List<String> points;
  final int quoteIndex;
  final List<_Act> actions;
  final List<String> decisions;
  final List<String> questions;

  /// `(startSec, speakerIndex, text)`.
  final List<(int, int, String)> transcript;
}

/// Popula o banco com os dados do design v3 (notas, resumos, ações, diário,
/// coleções) na primeira execução, para o app refletir os mockups. Idempotente:
/// não faz nada se já houver notas.
class DemoSeeder {
  DemoSeeder({
    required NoteRepository notes,
    required NoteAiRepository noteAi,
    required LibraryRepository library,
    required DiaryRepository diary,
    Uuid? uuid,
  }) : _notes = notes,
       _noteAi = noteAi,
       _library = library,
       _diary = diary,
       _uuid = uuid ?? const Uuid();

  final NoteRepository _notes;
  final NoteAiRepository _noteAi;
  final LibraryRepository _library;
  final DiaryRepository _diary;
  final Uuid _uuid;

  Future<void> seedIfEmpty() async {
    await _library.ensureBuiltinCollections();
    final existing = await _notes.getAllNotes();
    if (existing.isNotEmpty) return;

    final now = DateTime.now();
    for (final n in _notes_()) {
      await _seedNote(n, now);
    }
    // Entradas do diário para o calendário/sequência.
    //
    // Dias espalhados no começo do mês + uma sequência de 3 dias terminando
    // ONTEM (relativo a `now`), para a "Visão do mês" mostrar uma sequência
    // viva ("3 dias seguidos"), como no design. A sequência termina ontem
    // porque a entrada de hoje ainda não foi gravada.
    final days = <int>{1, 2, 3, 5, 6, 8, 9, 12, 13, 14, 15, 16};
    for (final offset in const [1, 2, 3]) {
      final date = DateTime(now.year, now.month, now.day - offset);
      if (date.month == now.month && date.year == now.year) {
        days.add(date.day);
      }
    }
    for (final day in days) {
      final date = DateTime(now.year, now.month, day);
      if (date.isAfter(now)) continue;
      await _diary.upsertEntry(day: date);
    }
  }

  Future<void> _seedNote(_DemoNote n, DateTime now) async {
    final base = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: n.ageDays))
        .add(Duration(hours: n.hour, minutes: n.minute));

    await _notes.insertNote(
      NotesCompanion.insert(
        id: n.id,
        title: Value(n.title),
        createdAt: base,
        updatedAt: base,
        durationMs: Value(n.durationSec * 1000),
        status: NoteStatus.ready,
        source: NoteSource.recording,
        folderId: Value(n.folder),
        favorite: Value(n.favorite),
        kind: Value(n.diary ? NoteKind.diary : NoteKind.note),
        aiStatus: const Value(AiStatus.ready),
        speakersJson: Value(n.speakers.join('\u001f')),
        playbackPath: Value('demo/${n.id}.m4a'),
      ),
    );

    // Segmentos.
    final drafts = <DraftSegment>[];
    for (var i = 0; i < n.transcript.length; i++) {
      final (startSec, spk, text) = n.transcript[i];
      final endSec = i + 1 < n.transcript.length
          ? n.transcript[i + 1].$1
          : startSec + 8;
      drafts.add(
        DraftSegment(
          speaker: spk == 0 ? SegmentSpeaker.me : SegmentSpeaker.others,
          startMs: startSec * 1000,
          endMs: endSec * 1000,
          content: text,
          wordsJson: TranscriptWord.encode(_words(text, startSec * 1000)),
        ),
      );
    }
    await _notes.replaceSegments(n.id, drafts);

    // note_ai.
    final others = n.speakers.where((s) => s != 'Você').toList();
    final speakerSegments = <SpeakerSegment>[
      for (var i = 0; i < n.transcript.length; i++)
        if (n.transcript[i].$2 > 0)
          SpeakerSegment(
            index: i,
            speaker: n.speakers[n.transcript[i].$2],
            inferred: true,
          ),
    ];
    final q = n.transcript.isEmpty ? null : n.transcript[n.quoteIndex];
    await _noteAi.saveNoteAi(
      n.id,
      NoteAi(
        title: n.title,
        tldr: n.tldr,
        points: n.points,
        quote: q == null
            ? null
            : NoteQuote(
                segmentIndex: n.quoteIndex,
                text: q.$3,
                speaker: n.speakers[q.$2],
                atMs: q.$1 * 1000,
              ),
        actions: n.actions
            .map((a) => NoteAction(text: a.text, owner: a.owner))
            .toList(),
        decisions: n.decisions,
        questions: n.questions,
        speakerNames: SpeakerNames(others: others, segments: speakerSegments),
      ),
    );

    // Ações (com estado done preservado).
    await _noteAi.replaceActions(
      n.id,
      n.actions.map((a) => NoteAction(text: a.text, owner: a.owner)).toList(),
      genId: _uuid.v4,
    );
    final rows = await _noteAi.allActions();
    for (final row in rows.where((r) => r.noteId == n.id)) {
      final match = n.actions.firstWhere(
        (a) => a.text == row.content,
        orElse: () => (text: '', owner: '', done: false),
      );
      if (match.done) await _noteAi.setActionDone(row.id, done: true);
    }
  }

  /// Sintetiza palavras com confiança: "Taís" fica em 0.42 (baixa) para o
  /// fluxo "Corrigir palavra"; o resto em ~0.97.
  List<TranscriptWord> _words(String text, int startMs) {
    final tokens = text.split(' ');
    final out = <TranscriptWord>[];
    var t = startMs;
    for (final tok in tokens) {
      final clean = tok.replaceAll(RegExp(r'[^\wÀ-ÿ]'), '');
      out.add(
        TranscriptWord(
          text: tok,
          startMs: t,
          endMs: t + 300,
          probability: clean == _lowConfWord ? 0.42 : 0.97,
        ),
      );
      t += 320;
    }
    return out;
  }

  List<_DemoNote> _notes_() => const [
    _DemoNote(
      id: 'n1',
      title: 'Kickoff do app de finanças pessoais',
      folder: 'trabalho',
      ageDays: 0,
      hour: 9,
      minute: 42,
      durationSec: 1102,
      favorite: true,
      speakers: ['Você', 'Camila', 'Rafael'],
      tldr:
          'Camila apresentou o escopo do MVP: controle de gastos por categoria '
          'e metas mensais. O time decidiu lançar só no iOS e validar com 200 '
          'usuários beta antes de investir em Open Finance.',
      points: [
        'MVP com três telas: visão do mês, categorias e metas.',
        'Open Finance fica para a segunda fase, por causa do custo e do prazo '
            'de certificação.',
        'Rafael estima seis semanas de desenvolvimento com o time atual.',
        'Entrevistas com usuários começam na semana que vem.',
      ],
      quoteIndex: 2,
      actions: [
        (
          text: 'Enviar a proposta revisada com o novo escopo',
          owner: 'Você · até sexta',
          done: false,
        ),
        (
          text: 'Agendar 5 entrevistas com usuários beta',
          owner: 'Camila',
          done: false,
        ),
        (
          text: 'Levantar o custo de certificação do Open Finance',
          owner: 'Rafael',
          done: true,
        ),
      ],
      decisions: [
        'Primeira versão apenas para iOS.',
        'Beta fechado com 200 pessoas da lista de espera.',
      ],
      questions: [
        'Modelo de receita: assinatura ou freemium?',
        'Quem aprova o design final do lado do cliente?',
      ],
      transcript: [
        (
          0,
          0,
          'Bom, acho que todo mundo já está aqui. A ideia hoje é alinhar o '
              'escopo do MVP antes de eu mandar a proposta final.',
        ),
        (
          64,
          1,
          'Perfeito. Do nosso lado, o essencial é a pessoa abrir o app e '
              'entender em dois segundos quanto já gastou no mês.',
        ),
        (
          188,
          1,
          'Se a pessoa não entende o mês em dois segundos, ela não volta. O '
              'resto é categoria e meta. Open Finance a gente quer, mas não '
              'precisa ser agora.',
        ),
        (
          352,
          2,
          'Concordo. Só a certificação leva uns dois meses, e a Taís do '
              'jurídico ainda precisa levantar o custo.',
        ),
        (
          497,
          0,
          'Então fica para a fase dois. E plataforma? Eu sugiro começar só com '
              'iOS e medir.',
        ),
        (
          640,
          1,
          'Faz sentido, setenta por cento da lista de espera usa iPhone.',
        ),
        (
          812,
          2,
          'Com esse escopo, eu diria seis semanas, considerando o time '
              'de hoje.',
        ),
        (1010, 0, 'Fechado. Vou revisar a proposta e mando até sexta.'),
      ],
    ),
    _DemoNote(
      id: 'n2',
      title: 'Ideia: podcast sobre ofícios',
      folder: 'ideias',
      ageDays: 0,
      hour: 7,
      minute: 15,
      durationSec: 192,
      speakers: ['Você'],
      tldr:
          'Uma série curta de entrevistas com artesãos de São Paulo, cada '
          'episódio gravado dentro da oficina, usando o som do trabalho como '
          'trilha.',
      points: [
        'Episódios de 20 minutos, um ofício por episódio.',
        'Primeiros nomes: marceneiro, encadernadora e luthier.',
        'Sem trilha musical: o som da oficina conduz a narrativa.',
      ],
      quoteIndex: 1,
      actions: [
        (text: 'Listar 10 possíveis entrevistados', owner: 'Você', done: false),
        (
          text: 'Testar microfone de lapela na oficina do Jorge',
          owner: 'Você',
          done: false,
        ),
      ],
      decisions: [],
      questions: ['Publicar também em vídeo ou só em áudio?'],
      transcript: [
        (
          0,
          0,
          'Ideia rápida antes que eu esqueça. Um podcast sobre ofícios, gente '
              'que ainda trabalha com as mãos aqui em São Paulo.',
        ),
        (
          41,
          0,
          'O som do trabalho é a trilha. A plaina, a agulha passando no papel, '
              'a afinação do violão.',
        ),
        (
          97,
          0,
          'Começaria com o Jorge, o marceneiro do bairro. Depois a '
              'encadernadora da Vila Madalena e um luthier.',
        ),
        (
          150,
          0,
          'Episódios curtos, uns vinte minutos. Preciso testar a captação de '
              'som lá dentro.',
        ),
      ],
    ),
    _DemoNote(
      id: 'n3',
      title: 'Consulta com a Dra. Marina',
      folder: 'pessoal',
      ageDays: 3,
      hour: 16,
      minute: 30,
      durationSec: 588,
      speakers: ['Você', 'Dra. Marina'],
      tldr:
          'Retorno de rotina. A recomendação é ajustar o horário de sono, '
          'voltar à atividade física três vezes por semana e repetir os exames '
          'em dois meses.',
      points: [
        'Dormir antes da meia-noite pelo menos cinco dias por semana.',
        'Caminhada ou musculação três vezes por semana.',
        'Exame de sangue em jejum antes do retorno.',
      ],
      quoteIndex: 1,
      actions: [
        (text: 'Fazer exame de sangue em jejum', owner: 'Você', done: false),
        (
          text: 'Marcar retorno para daqui a 60 dias',
          owner: 'Você',
          done: false,
        ),
      ],
      decisions: ['Sem mudança de medicação por enquanto.'],
      questions: ['Vale incluir acompanhamento com nutricionista?'],
      transcript: [
        (
          0,
          1,
          'Então, olhando os resultados, está tudo dentro do esperado. O ponto '
              'de atenção é o sono.',
        ),
        (
          130,
          1,
          'Mais do que qualquer remédio, o que muda esse quadro é '
              'regularidade: horário para dormir e atividade física.',
        ),
        (302, 0, 'Entendi. E quando eu volto?'),
        (340, 1, 'Daqui a uns dois meses, já com um exame novo em jejum.'),
      ],
    ),
    _DemoNote(
      id: 'n4',
      title: 'Aula 7 — Heurísticas de Nielsen',
      folder: 'estudos',
      ageDays: 4,
      hour: 10,
      minute: 0,
      durationSec: 2535,
      speakers: ['Prof. Lúcia'],
      tldr:
          'Revisão das dez heurísticas de usabilidade, com foco em '
          'visibilidade do estado do sistema e prevenção de erros. A avaliação '
          'heurística em grupo será o trabalho final.',
      points: [
        'Visibilidade do estado: o sistema precisa sempre informar o que está '
            'acontecendo.',
        'Prevenir o erro vale mais do que escrever uma boa mensagem de erro.',
        'Avaliações com 3 a 5 avaliadores encontram a maior parte dos '
            'problemas.',
      ],
      quoteIndex: 1,
      actions: [
        (
          text: 'Escolher o app para a avaliação heurística',
          owner: 'Grupo',
          done: false,
        ),
        (text: 'Ler o capítulo 5 do livro-texto', owner: 'Você', done: false),
      ],
      decisions: ['Trabalho final em grupos de três.'],
      questions: ['A entrega aceita vídeo ou só relatório?'],
      transcript: [
        (
          0,
          0,
          'Hoje a gente fecha as heurísticas. Começando pela primeira, que é a '
              'mais violada: visibilidade do estado do sistema.',
        ),
        (
          610,
          0,
          'Uma boa mensagem de erro é ótima, mas o melhor erro é aquele que '
              'nunca acontece.',
        ),
        (
          1480,
          0,
          'Com três a cinco avaliadores vocês encontram a maior parte dos '
              'problemas. Por isso os grupos serão de três.',
        ),
      ],
    ),
    _DemoNote(
      id: 'n5',
      title: 'Roadmap do primeiro trimestre',
      folder: 'trabalho',
      ageDays: 9,
      hour: 14,
      minute: 20,
      durationSec: 1503,
      speakers: ['Você', 'Bruno'],
      tldr:
          'Prioridades do trimestre: estabilizar a sincronização, lançar a '
          'busca nova e adiar o redesign do painel para abril.',
      points: [
        'Sincronização é prioridade número um pelo volume de reclamações.',
        'Busca nova entra em fevereiro.',
        'Redesign do painel fica para abril.',
      ],
      quoteIndex: 1,
      actions: [
        (
          text: 'Escrever o documento de requisitos da busca',
          owner: 'Bruno',
          done: false,
        ),
        (
          text: 'Comunicar a mudança de data do redesign',
          owner: 'Você',
          done: true,
        ),
      ],
      decisions: ['Redesign do painel adiado para abril.'],
      questions: ['Precisamos contratar mais uma pessoa de backend?'],
      transcript: [
        (0, 0, 'Vamos olhar o trimestre inteiro. O que não pode esperar?'),
        (
          220,
          1,
          'Sincronização. A Taís do suporte mostrou que metade dos tickets da '
              'semana passada são sobre isso.',
        ),
        (
          690,
          0,
          'Então o redesign do painel vai para abril. Eu aviso o time.',
        ),
      ],
    ),
    _DemoNote(
      id: 'n6',
      title: 'Lista do fim de semana',
      folder: 'pessoal',
      ageDays: 12,
      hour: 11,
      minute: 2,
      durationSec: 48,
      speakers: ['Você'],
      tldr: 'Compras para o almoço de domingo e duas tarefas da casa.',
      points: [
        'Feira: tomate, manjericão, limão e pão.',
        'Buscar a encomenda na portaria.',
        'Trocar a lâmpada da varanda.',
      ],
      quoteIndex: 0,
      actions: [
        (text: 'Feira de domingo', owner: 'Você', done: true),
        (text: 'Buscar encomenda na portaria', owner: 'Você', done: false),
        (text: 'Trocar a lâmpada da varanda', owner: 'Você', done: false),
      ],
      decisions: [],
      questions: ['Convidar a Ana para o almoço?'],
      transcript: [
        (0, 0, 'Pra domingo: tomate, manjericão, limão e um pão bom.'),
        (
          22,
          0,
          'E não esquecer da encomenda na portaria e da lâmpada da varanda.',
        ),
      ],
    ),
    // ---- Diário ----
    _DemoNote(
      id: 'd1',
      title: 'Um dia mais leve',
      folder: 'diario',
      ageDays: 1,
      hour: 22,
      minute: 10,
      durationSec: 214,
      diary: true,
      speakers: ['Você'],
      tldr:
          'Dia produtivo depois de uma noite bem dormida. A corrida da manhã '
          'ajudou a começar com energia e a proposta avançou bastante.',
      points: [
        'Dormir antes da meia-noite fez diferença.',
        'Corrida de manhã antes do trabalho.',
        'Proposta quase pronta.',
      ],
      quoteIndex: 0,
      actions: [],
      decisions: [],
      questions: ['Dá para manter o horário de sono no fim de semana?'],
      transcript: [
        (
          0,
          0,
          'Hoje foi um dia mais leve. Dormi cedo ontem e acordei sem '
              'despertador.',
        ),
        (
          62,
          0,
          'Corri antes do trabalho e a manhã rendeu. A proposta está quase '
              'pronta.',
        ),
        (140, 0, 'Quero repetir isso amanhã.'),
      ],
    ),
    _DemoNote(
      id: 'd2',
      title: 'Ansiedade antes do kickoff',
      folder: 'diario',
      ageDays: 3,
      hour: 23,
      minute: 2,
      durationSec: 176,
      diary: true,
      speakers: ['Você'],
      tldr:
          'Noite agitada pensando no kickoff do app de finanças. Escrever a '
          'pauta ajudou a organizar a cabeça.',
      points: [
        'Preocupação com o escopo do cliente.',
        'Escrever a pauta acalmou.',
      ],
      quoteIndex: 0,
      actions: [],
      decisions: [],
      questions: ['O que está fora do meu controle nessa reunião?'],
      transcript: [
        (
          0,
          0,
          'Estou meio ansioso com o kickoff. Fico pensando se o escopo vai '
              'caber no prazo.',
        ),
        (88, 0, 'Escrevi a pauta e já me sinto melhor.'),
      ],
    ),
    _DemoNote(
      id: 'd3',
      title: 'Domingo com a família',
      folder: 'diario',
      ageDays: 5,
      hour: 21,
      minute: 40,
      durationSec: 241,
      diary: true,
      speakers: ['Você'],
      tldr:
          'Almoço longo na casa da mãe, sem celular. Um dia de descanso de '
          'verdade.',
      points: ['Almoço na casa da mãe.', 'Dia inteiro longe do trabalho.'],
      quoteIndex: 0,
      actions: [],
      decisions: [],
      questions: ['Fazer isso todo mês?'],
      transcript: [
        (
          0,
          0,
          'Passei o dia na casa da minha mãe. Deixei o celular na bolsa e nem '
              'senti falta.',
        ),
        (120, 0, 'Preciso de mais domingos assim.'),
      ],
    ),
  ];
}
