import 'dart:convert';
import 'dart:typed_data';

import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/domain/note_ai.dart';

String _speakerLabel(SegmentSpeaker s) =>
    s == SegmentSpeaker.me ? 'Eu' : 'Outros';

String formatTimestamp(int ms) {
  final d = Duration(milliseconds: ms);
  final minutes = d.inMinutes.toString().padLeft(2, '0');
  final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// Transcrição em texto puro, uma linha por segmento com falante e tempo.
String transcriptPlainText(List<SegmentRow> segments) {
  return segments
      .map(
        (s) =>
            '[${formatTimestamp(s.startMs)}] '
            '${_speakerLabel(s.speaker)}: ${s.content}',
      )
      .join('\n');
}

/// Exportação .md: título, metadados e transcrição.
String noteMarkdown(
  NoteRow note,
  List<SegmentRow> segments,
  List<TagRow> tags,
) {
  final buffer = StringBuffer()
    ..writeln('# ${note.title.isEmpty ? 'Sem título' : note.title}')
    ..writeln();
  if (tags.isNotEmpty) {
    final rendered = tags
        .map((t) => '${t.emoji == null ? '' : '${t.emoji} '}${t.name}')
        .join(', ');
    buffer
      ..writeln('**Tags:** $rendered')
      ..writeln();
  }
  for (final s in segments) {
    buffer.writeln(
      '- `${formatTimestamp(s.startMs)}` **${_speakerLabel(s.speaker)}:** '
      '${s.content}',
    );
  }
  return buffer.toString();
}

/// Exportação .txt (texto puro).
String noteTxt(NoteRow note, List<SegmentRow> segments) {
  final buffer = StringBuffer()
    ..writeln(note.title.isEmpty ? 'Sem título' : note.title)
    ..writeln()
    ..write(transcriptPlainText(segments));
  return buffer.toString();
}

/// Resumo (.md): título, TL;DR, pontos principais, decisões e ações.
///
/// Usa o [NoteAi] já gerado; campos vazios são omitidos para o arquivo ficar
/// limpo mesmo em notas curtas.
String summaryMarkdown(NoteRow note, NoteAi? ai) {
  final buffer = StringBuffer()
    ..writeln('# ${note.title.isEmpty ? 'Sem título' : note.title}')
    ..writeln();
  if (ai == null) {
    buffer.writeln('_Resumo ainda não gerado._');
    return buffer.toString();
  }
  if (ai.tldr.trim().isNotEmpty) {
    buffer
      ..writeln(ai.tldr.trim())
      ..writeln();
  }
  if (ai.points.isNotEmpty) {
    buffer.writeln('## Pontos principais');
    for (final p in ai.points) {
      buffer.writeln('- $p');
    }
    buffer.writeln();
  }
  if (ai.decisions.isNotEmpty) {
    buffer.writeln('## Decisões');
    for (final d in ai.decisions) {
      buffer.writeln('- $d');
    }
    buffer.writeln();
  }
  if (ai.actions.isNotEmpty) {
    buffer.writeln('## Ações');
    for (final a in ai.actions) {
      final owner = (a.owner ?? '').trim();
      final ownerText = owner.isEmpty ? '' : ' — $owner';
      buffer.writeln('- [ ] ${a.text}$ownerText');
    }
    buffer.writeln();
  }
  return buffer.toString();
}

/// Uma entrada de um arquivo .zip: nome e bytes.
typedef ZipEntry = ({String name, List<int> bytes});

/// Monta um arquivo .zip (método "store", sem compressão) a partir de
/// [entries]. Implementação pura em Dart para não depender de pacote externo;
/// suficiente para empacotar áudio + textos de uma nota.
List<int> buildZip(List<ZipEntry> entries) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  var offset = 0;

  void writeUint16(BytesBuilder b, int v) {
    b
      ..addByte(v & 0xFF)
      ..addByte((v >> 8) & 0xFF);
  }

  void writeUint32(BytesBuilder b, int v) {
    b
      ..addByte(v & 0xFF)
      ..addByte((v >> 8) & 0xFF)
      ..addByte((v >> 16) & 0xFF)
      ..addByte((v >> 24) & 0xFF);
  }

  for (final entry in entries) {
    final nameBytes = _utf8Bytes(entry.name);
    final data = entry.bytes;
    final crc = _crc32(data);

    // Local file header.
    final local = BytesBuilder();
    writeUint32(local, 0x04034b50);
    writeUint16(local, 20); // versão mínima
    writeUint16(local, 0); // flags
    writeUint16(local, 0); // método: store
    writeUint16(local, 0); // hora
    writeUint16(local, 0); // data
    writeUint32(local, crc);
    writeUint32(local, data.length); // tamanho comprimido
    writeUint32(local, data.length); // tamanho original
    writeUint16(local, nameBytes.length);
    writeUint16(local, 0); // extra
    local
      ..add(nameBytes)
      ..add(data);
    final localBytes = local.toBytes();
    out.add(localBytes);

    // Central directory entry.
    writeUint32(central, 0x02014b50);
    writeUint16(central, 20); // versão criadora
    writeUint16(central, 20); // versão mínima
    writeUint16(central, 0);
    writeUint16(central, 0); // método: store
    writeUint16(central, 0);
    writeUint16(central, 0);
    writeUint32(central, crc);
    writeUint32(central, data.length);
    writeUint32(central, data.length);
    writeUint16(central, nameBytes.length);
    writeUint16(central, 0);
    writeUint16(central, 0);
    writeUint16(central, 0);
    writeUint16(central, 0);
    writeUint32(central, 0);
    writeUint32(central, offset);
    central.add(nameBytes);

    offset += localBytes.length;
  }

  final centralBytes = central.toBytes();
  out.add(centralBytes);

  // End of central directory record.
  final end = BytesBuilder();
  writeUint32(end, 0x06054b50);
  writeUint16(end, 0);
  writeUint16(end, 0);
  writeUint16(end, entries.length);
  writeUint16(end, entries.length);
  writeUint32(end, centralBytes.length);
  writeUint32(end, offset);
  writeUint16(end, 0);
  out.add(end.toBytes());

  return out.toBytes();
}

List<int> _utf8Bytes(String s) => const Utf8Encoder().convert(s);

/// CRC-32 (IEEE) usado no formato zip.
int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      final mask = -(crc & 1);
      crc = (crc >> 1) ^ (0xEDB88320 & mask);
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
