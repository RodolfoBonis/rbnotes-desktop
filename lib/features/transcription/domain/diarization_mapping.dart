/// Um segmento para a diarização (índice na lista completa, intervalo em ms e
/// se é de "Outros" — só esses recebem rótulo de falante).
typedef DiarSegment = ({int index, int startMs, int endMs, bool isOthers});

/// Um turno de fala vindo da diarização local (sherpa-onnx): intervalo e o id
/// do agrupamento acústico (`speaker`).
typedef DiarTurn = ({int startMs, int endMs, int speaker});

/// Mapeia os turnos de diarização aos segmentos de "Outros" por **maior
/// sobreposição temporal** e devolve `índiceDoSegmento → "Pessoa N"`.
///
/// Os ids são renumerados por ordem de aparição, para os rótulos ficarem
/// estáveis e legíveis ("Pessoa 1", "Pessoa 2"…). Segmentos de "Outros" sem
/// turno sobreposto ficam de fora (o display cai para "Outros").
Map<int, String> assignDiarizationLabels({
  required List<DiarSegment> segments,
  required List<DiarTurn> turns,
}) {
  if (turns.isEmpty) return const {};

  final speakerOf = <int, int>{}; // segmentIndex → speaker cluster id
  for (final seg in segments) {
    if (!seg.isOthers) continue;
    var bestSpeaker = -1;
    var bestOverlap = 0;
    for (final turn in turns) {
      final overlap =
          (seg.endMs < turn.endMs ? seg.endMs : turn.endMs) -
          (seg.startMs > turn.startMs ? seg.startMs : turn.startMs);
      if (overlap > bestOverlap) {
        bestOverlap = overlap;
        bestSpeaker = turn.speaker;
      }
    }
    if (bestSpeaker >= 0) speakerOf[seg.index] = bestSpeaker;
  }

  // Renumera os clusters por ordem de aparição (determinístico pela ordem dos
  // segmentos de "Outros").
  final order = <int, int>{}; // clusterId → 1-based
  final labels = <int, String>{};
  for (final seg in segments) {
    final cluster = speakerOf[seg.index];
    if (cluster == null) continue;
    final n = order.putIfAbsent(cluster, () => order.length + 1);
    labels[seg.index] = 'Pessoa $n';
  }
  return labels;
}
