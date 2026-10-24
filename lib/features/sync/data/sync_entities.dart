/// Nomes das entidades sincronizáveis (iguais ao contrato/backend).
///
/// Fica num arquivo próprio (sem dependências de drift/mappers) para poder ser
/// referenciado também pela camada de dados (ex.: `NoteRepository` ao marcar o
/// `segment_set` como sujo no `sync_meta`) sem acoplar ao mapeamento completo.
abstract final class SyncEntities {
  static const note = 'note';
  static const segmentSet = 'segment_set';
  static const folder = 'folder';
  static const action = 'action';
  static const collection = 'collection';
  static const vocabulary = 'vocabulary';
  static const chatMessage = 'chat_message';
  static const noteAi = 'note_ai';
  static const diaryEntry = 'diary_entry';
  static const tag = 'tag';
  static const noteTag = 'note_tag';

  static const List<String> all = [
    note,
    segmentSet,
    folder,
    action,
    collection,
    vocabulary,
    chatMessage,
    noteAi,
    diaryEntry,
    tag,
    noteTag,
  ];
}
