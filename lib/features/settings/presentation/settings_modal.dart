import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rbnotes/app/theme_mode_cubit.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/core/ui/rb_select.dart';
import 'package:rbnotes/core/ui/traffic_lights.dart';
import 'package:rbnotes/features/ai/data/ai_client.dart';
import 'package:rbnotes/features/ai/data/ai_usage_client.dart';
import 'package:rbnotes/features/ai/presentation/ai_usage_cubit.dart';
import 'package:rbnotes/features/dictation/data/dictation_service.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/recording/data/mac_key_codes.dart';
import 'package:rbnotes/features/recording/data/record_note_hotkey_service.dart';
import 'package:rbnotes/features/security/data/note_key_store.dart';
import 'package:rbnotes/features/security/presentation/app_lock_cubit.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/settings/data/vocabulary_repository.dart';
import 'package:rbnotes/features/settings/presentation/accent_picker.dart';
import 'package:rbnotes/features/settings/presentation/ai_usage_pane.dart';
import 'package:rbnotes/features/settings/presentation/recovery_key_dialog.dart';
import 'package:rbnotes/features/settings/presentation/vocabulary_editor.dart';
import 'package:rbnotes/features/sync/data/audio_upload_queue.dart';
import 'package:rbnotes/features/sync/data/sync_service.dart';
import 'package:rbnotes/features/sync/data/sync_status.dart';
import 'package:rbnotes/features/sync/presentation/audio_queue_panel.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:rbnotes/notifications/notifier.dart';
import 'package:url_launcher/url_launcher.dart';

/// Rótulos, tamanhos e descrições dos 5 modelos Whisper (design v3).
const whisperModelInfo = <WhisperModel, (String, String, String)>{
  WhisperModel.tiny: (
    'Tiny',
    '75 MB',
    'Instantâneo, ideal para lembretes curtos',
  ),
  WhisperModel.smallQ5: (
    'Small',
    '466 MB',
    'Equilíbrio para notas do dia a dia',
  ),
  WhisperModel.medium: (
    'Medium',
    '1,5 GB',
    'Mais preciso com sotaques e ruído',
  ),
  WhisperModel.largeV3TurboQ5: (
    'Large v3 Turbo',
    '1,6 GB',
    'Recomendado para Apple Silicon',
  ),
  WhisperModel.largeV3: ('Large v3', '3,1 GB', 'Máxima precisão, mais lento'),
};

enum SettingsTab {
  geral,
  gravacao,
  transcricao,
  ia,
  conta,
  uso,
  atalhos,
  privacidade,
}

/// Janela modal de Configurações com as 7 abas do design v3.
class SettingsModal extends StatefulWidget {
  const SettingsModal({
    required this.store,
    required this.native,
    required this.vocabulary,
    required this.recordNoteHotkey,
    required this.aiUsageClient,
    required this.userName,
    required this.userEmail,
    required this.userInitials,
    required this.onClose,
    required this.onLogout,
    required this.onEraseAllData,
    this.dictation,
    this.noteKeyStore,
    this.onMenuBarChanged,
    this.onRecoveryKeyChanged,
    this.notifier,
    this.onNotificationsChanged,
    this.sync,
    this.audioQueue,
    this.notes,
    super.key,
  });

  final SettingsStore store;
  final RbNative native;
  final VocabularyRepository vocabulary;

  /// Registra o atalho global "Gravar nota" e expõe o estado do registro para
  /// a aba Atalhos.
  final RecordNoteHotkeyService recordNoteHotkey;

  /// Cliente de consumo de IA para a aba "Uso" (GET /v1/ai/usage).
  final AiUsageClient aiUsageClient;

  /// Ditado global, para o editor do atalho de ditado (aba Gravação). Null em
  /// testes/goldens: a linha cai para o atalho estático.
  final DictationService? dictation;

  /// Chave das notas bloqueadas (aba Privacidade → "Chave de recuperação").
  /// Null esconde a linha (ex.: em testes de golden do shell).
  final NoteKeyStore? noteKeyStore;

  /// Chamado ao alternar "Mostrar na barra de menus" (mostra/remove a tray ao
  /// vivo). Null em testes sem a casca do app.
  final ValueChanged<bool>? onMenuBarChanged;

  /// Chamado após importar/gerar a chave (invalida o cache do SyncCrypto).
  final VoidCallback? onRecoveryKeyChanged;

  /// Notifier para o status/pedido de permissão de notificações.
  final Notifier? notifier;

  /// Chamado após mudar um toggle de notificação (reagenda).
  final VoidCallback? onNotificationsChanged;
  final String userName;
  final String userEmail;
  final String userInitials;
  final VoidCallback onClose;
  final VoidCallback onLogout;

  /// Apaga todas as notas, áudios e dados locais (ação destrutiva da aba
  /// Privacidade).
  final Future<void> Function() onEraseAllData;

  /// Sync real (quando o backend está ligado): habilita o status ao vivo e o
  /// botão "Sincronizar agora" na aba Conta. Null = local-first (estático).
  final SyncService? sync;

  /// Fila de upload de áudio (só com backend): habilita "Enviar áudios" e a
  /// visualização da fila. Null = sem backend.
  final AudioUploadQueue? audioQueue;

  /// Repositório de notas, para resolver títulos na fila de upload.
  final NoteRepository? notes;

  @override
  State<SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends State<SettingsModal> {
  SettingsTab _tab = SettingsTab.geral;
  int _vocabCount = 0;
  final _downloaded = <WhisperModel>{};
  final _downloading = <WhisperModel, double>{};
  final _subs = <WhisperModel, StreamSubscription<double>>{};
  StreamSubscription<RecordNoteHotkeyStatus>? _recordHotkeySub;
  StreamSubscription<DictationHotkeyStatus>? _dictationSub;
  bool? _notifPermission;
  List<AudioInputDevice> _micDevices = const [];

  SettingsStore get _s => widget.store;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshModels());
    unawaited(_refreshVocabCount());
    // Reflete a (re)registração do atalho "Gravar nota" ao vivo na aba Atalhos.
    _recordHotkeySub = widget.recordNoteHotkey.statusChanges.listen((_) {
      if (mounted) setState(() {});
    });
    _dictationSub = widget.dictation?.statusChanges.listen((_) {
      if (mounted) setState(() {});
    });
    unawaited(_loadNotifPermission());
    unawaited(_loadMicDevices());
  }

  Future<void> _loadMicDevices() async {
    try {
      final devices = await widget.native.inputDevices();
      if (mounted) setState(() => _micDevices = devices);
    } on Object {
      // sem plugin em teste; mantém o fallback do nome salvo.
    }
  }

  Future<void> _loadNotifPermission() async {
    final status = await widget.notifier?.isPermissionGranted();
    if (mounted) setState(() => _notifPermission = status);
  }

  Future<void> _refreshVocabCount() async {
    final terms = await widget.vocabulary.getTerms();
    if (mounted) setState(() => _vocabCount = terms.length);
  }

  Future<void> _refreshModels() async {
    for (final m in WhisperModel.values) {
      final state = await widget.native.modelState(m);
      if (state.downloaded && mounted) {
        setState(() => _downloaded.add(m));
      }
    }
  }

  void _download(WhisperModel model) {
    setState(() => _downloading[model] = 0);
    _subs[model] = widget.native
        .downloadModel(model)
        .listen(
          (p) => setState(() => _downloading[model] = p),
          onDone: () => setState(() {
            _downloading.remove(model);
            _downloaded.add(model);
          }),
          onError: (Object _) => setState(() => _downloading.remove(model)),
        );
  }

  @override
  void dispose() {
    for (final s in _subs.values) {
      unawaited(s.cancel());
    }
    unawaited(_recordHotkeySub?.cancel());
    unawaited(_dictationSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return GestureDetector(
      onTap: widget.onClose,
      behavior: HitTestBehavior.opaque,
      child: ColoredBox(
        color: const Color(0x241E1914),
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 700,
                height: 580,
                decoration: BoxDecoration(
                  color: rb.bg3,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: rb.onSurface(0.22), width: 0.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x4D000000),
                      blurRadius: 80,
                      offset: Offset(0, 30),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _TabStrip(
                      tab: _tab,
                      onTab: (t) => setState(() => _tab = t),
                      onClose: widget.onClose,
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(32, 22, 32, 30),
                        child: _buildPane(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPane(BuildContext context) {
    return switch (_tab) {
      SettingsTab.geral => _geral(),
      SettingsTab.gravacao => _gravacao(),
      SettingsTab.transcricao => _transcricao(),
      SettingsTab.ia => _ia(),
      SettingsTab.conta => _conta(),
      SettingsTab.uso => _uso(),
      SettingsTab.atalhos => _atalhos(),
      SettingsTab.privacidade => _privacidade(),
    };
  }

  // ---------------- panes ----------------

  Widget _geral() => _Groups([
    _Group(
      rows: [
        _segRow(
          'Aparência',
          const ['Sistema', 'Claro', 'Escuro'],
          _appearanceLabel(context.watch<ThemeModeCubit>().state),
          (v) => context.read<ThemeModeCubit>().set(_themeFor(v)),
        ),
        const _SettingRow(
          label: 'Cor de acento',
          trailing: AccentSwatches(),
        ),
        _toggle(
          'Abrir ao iniciar sessão',
          null,
          _s.launchAtLogin,
          (v) {
            unawaited(_s.setLaunchAtLogin(value: v));
            unawaited(widget.native.setLaunchAtLogin(v));
          },
        ),
        _toggle(
          'Mostrar na barra de menus',
          'Grave de qualquer app pelo ícone na barra',
          _s.showInMenuBar,
          (v) {
            unawaited(_s.setShowInMenuBar(value: v));
            widget.onMenuBarChanged?.call(v);
          },
        ),
        _select(
          'Pasta para novas notas',
          const ['Ideias', 'Trabalho', 'Pessoal', 'Estudos'],
          _folderLabel(_s.defaultFolder),
          (v) => _s.setDefaultFolder(_folderId(v)),
        ),
      ],
    ),
    _Group(
      title: 'Notificações',
      foot: _notifPermission == false
          ? 'As notificações estão desativadas no macOS. Toque em "Pedir '
                'permissão" ou libere em Ajustes do Sistema.'
          : null,
      rows: [
        if (widget.notifier != null) _permissionRow(),
        _notifToggle(
          'Nota pronta',
          'Avisa quando a transcrição e o resumo terminam',
          _s.noteReadyNotif,
          (v) => _s.setNoteReadyNotif(value: v),
        ),
        _notifToggle(
          'Tarefas com prazo',
          'Lembra no dia do prazo, às 9h',
          _s.remindTasks,
          (v) => _s.setRemindTasks(value: v),
        ),
        _notifToggle(
          'Pergunta do diário',
          'Todo dia às 21h, a pergunta do dia seguinte',
          _s.diaryPromptNotif,
          (v) => _s.setDiaryPromptNotif(value: v),
        ),
        _notifToggle(
          'Resumo semanal',
          'Toda segunda, um panorama das suas notas e tarefas',
          _s.weeklySummary,
          (v) => _s.setWeeklySummary(value: v),
        ),
      ],
    ),
  ]);

  Widget _notifToggle(
    String label,
    String? sub,
    bool value,
    ValueChanged<bool> onChanged,
  ) => _toggle(label, sub, value, (v) {
    onChanged(v);
    widget.onNotificationsChanged?.call();
  });

  Widget _permissionRow() => _SettingRow(
    label: 'Permissão de notificações',
    sub: switch (_notifPermission) {
      true => 'Concedida',
      false => 'Negada',
      null => 'Desconhecida',
    },
    trailing: _PillButton(label: 'Pedir permissão', onTap: _askNotifPermission),
  );

  Future<void> _askNotifPermission() async {
    final granted = await widget.notifier?.requestPermission();
    if (mounted) setState(() => _notifPermission = granted);
  }

  Widget _gravacao() => _Groups([
    _Group(
      rows: [
        _micRow(),
        if (widget.dictation != null) ...[
          _dictationRow(),
          if (_s.dictationEnabled) _dictationModeRow(),
        ] else
          _keys('Atalho de ditado', const ['⌥', 'Espaço']),
        _toggle(
          'Gravar áudio do sistema',
          'Capta as duas vozes em chamadas no Meet, Zoom e Teams',
          _s.captureSystemAudio,
          (v) => _s.setCaptureSystemAudio(value: v),
        ),
        _toggle(
          'Sugerir gravação ao detectar reunião',
          null,
          _s.autoMeet,
          (v) => _s.setAutoMeet(value: v),
        ),
      ],
    ),
    _Group(
      title: 'Qualidade',
      rows: [
        _toggle(
          'Redução de ruído',
          null,
          _s.noiseReduction,
          (v) => _s.setNoiseReduction(value: v),
        ),
        _toggle(
          'Remover silêncios longos',
          'O áudio original é preservado',
          _s.removeSilences,
          (v) => _s.setRemoveSilences(value: v),
        ),
      ],
    ),
  ]);

  Widget _transcricao() => _Groups([
    _Group(
      title: 'Modelo Whisper',
      foot:
          'Os modelos rodam no Neural Engine do seu Mac. Nenhum áudio é '
          'enviado para a internet.',
      rows: [for (final m in WhisperModel.values) _modelRow(m)],
    ),
    _Group(
      rows: [
        _select(
          'Idioma',
          const [
            'Detectar automaticamente',
            'Português (Brasil)',
            'English',
            'Español',
          ],
          _s.language,
          _s.setLanguage,
        ),
        _toggle(
          'Identificar falantes',
          null,
          _s.identifySpeakers,
          (v) => _s.setIdentifySpeakers(value: v),
        ),
        _button(
          'Vocabulário personalizado',
          'Nomes e termos que o Whisper deve reconhecer · '
              '$_vocabCount ${_vocabCount == 1 ? 'termo' : 'termos'}',
          'Editar',
          onTap: _openVocabularyEditor,
        ),
      ],
    ),
  ]);

  Widget _ia() => _Groups([
    _Group(
      rows: [
        _toggle(
          'Gerar resumo automaticamente',
          null,
          _s.autoSummary,
          (v) => _s.setAutoSummary(value: v),
        ),
        _toggle(
          'Extrair tarefas e decisões',
          null,
          _s.extractTasks,
          (v) => _s.setExtractTasks(value: v),
        ),
        _select(
          'Estilo do resumo',
          const ['Objetivo', 'Detalhado', 'Em tópicos'],
          _styleLabel(_s.summaryStyle),
          (v) => _s.setSummaryStyle(_style(v)),
        ),
        _select(
          'Tamanho',
          const ['Curto', 'Médio', 'Longo'],
          _lengthLabel(_s.summaryLength),
          (v) => _s.setSummaryLength(_length(v)),
        ),
        _select(
          'Modelo',
          const ['Claude Sonnet', 'Claude Opus', 'Claude Haiku'],
          _s.aiModel,
          _s.setAiModel,
        ),
      ],
    ),
    _Group(
      title: 'Privacidade',
      foot:
          'O Claude recebe apenas o texto transcrito. O áudio só sobe se '
          '"Enviar áudios" estiver ligado.',
      rows: [
        _toggle(
          'Não enviar notas da pasta Pessoal',
          'Essas notas ficam só com a transcrição local',
          _s.skipPersonal,
          (v) => _s.setSkipPersonal(value: v),
        ),
        _toggle(
          'Mascarar dados sensíveis',
          'CPF, telefones e números de cartão são ocultados antes do envio',
          _s.redactSensitive,
          (v) => _s.setRedactSensitive(value: v),
        ),
      ],
    ),
  ]);

  Widget _conta() => _Groups([
    _Group(rows: [_profileRow()]),
    _Group(
      title: 'Sincronização',
      rows: [
        _toggle(
          'Sincronizar entre dispositivos',
          'Suas notas sincronizam entre seus Macs. Notas bloqueadas sobem '
              'cifradas de ponta a ponta.',
          _s.syncEnabled,
          (v) {
            unawaited(_s.setSyncEnabled(value: v));
            widget.sync?.onEnabledChanged(enabled: v);
          },
        ),
        if (widget.sync != null)
          _syncStatusRow(widget.sync!)
        else
          _status('Última sincronização', 'há 2 minutos'),
        if (widget.audioQueue != null) ...[
          _toggle(
            'Enviar áudios',
            'Sobe o áudio das notas para abrir em outro Mac. Separado do '
                'texto, que sempre sincroniza.',
            _s.sendAudio,
            (v) {
              unawaited(_s.setSendAudio(value: v));
              if (v) unawaited(widget.audioQueue!.process());
            },
          ),
          if (_s.sendAudio) _audioQueueRow(),
        ],
      ],
    ),
    _Group(
      rows: [
        _button(
          'Sessão neste Mac',
          widget.userEmail,
          'Sair',
          onTap: widget.onLogout,
          destructive: true,
        ),
      ],
    ),
  ]);

  Widget _audioQueueRow() => StreamBuilder<List<AudioUploadItem>>(
    stream: widget.audioQueue!.items,
    initialData: widget.audioQueue!.current,
    builder: (context, snap) {
      final items = snap.data ?? const [];
      final failed = items
          .where((i) => i.status == AudioUploadStatus.failed)
          .length;
      final sub = items.isEmpty
          ? 'Tudo enviado'
          : failed > 0
          ? '$failed com falha · ${items.length} na fila'
          : '${items.length} na fila';
      return _button('Fila de upload', sub, 'Ver', onTap: _openAudioQueue);
    },
  );

  Future<void> _openAudioQueue() async {
    final notes = widget.notes;
    if (notes == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AudioQueueDialog(queue: widget.audioQueue!, notes: notes),
    );
  }

  Widget _uso() => BlocProvider(
    create: (_) {
      final cubit = AiUsageCubit(client: widget.aiUsageClient);
      unawaited(cubit.start());
      return cubit;
    },
    child: const AiUsagePane(),
  );

  Widget _atalhos() => _Groups([
    _Group(
      title: 'Atalho global',
      foot:
          'Funciona em qualquer app. Toque para iniciar e toque de novo para '
          'concluir a nota (o resumo é gerado automaticamente).',
      rows: [
        _recordNoteRow(),
      ],
    ),
    _Group(
      title: 'No app',
      rows: [
        _keys('Nova gravação', const ['⌘', 'R']),
        _keys('Perguntar às notas', const ['⌘', 'K']),
        _keys('Tocar ou pausar', const ['Espaço']),
        _keys('Buscar', const ['⌘', 'F']),
        _keys('Ajustes', const ['⌘', ',']),
      ],
    ),
  ]);

  Widget _dictationRow() {
    final status = widget.dictation!.hotkeyStatus;
    final enabled = _s.dictationEnabled;
    final sub = switch (status) {
      _ when !enabled => 'Desativado',
      DictationHotkeyStatus(hasError: true) =>
        'Não foi possível registrar: '
            '${status.error}',
      _ => 'Dite em qualquer app; o texto é colado no foco',
    };
    return _SettingRow(
      label: 'Ditado',
      sub: sub,
      subColor: status.hasError && enabled ? RbTokens.destructive : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (enabled) ...[
            _Keys(keys: MacKeyCodes.symbols(_s.hotkey)),
            const SizedBox(width: 10),
            _PillButton(label: 'Alterar', onTap: _changeDictationHotkey),
            const SizedBox(width: 8),
          ],
          _Toggle(
            value: enabled,
            onChanged: (v) async {
              await _s.setDictationEnabled(value: v);
              await widget.dictation!.applySettings();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _dictationModeRow() => _segRow(
    'Modo do ditado',
    const ['Segurar', 'Alternar'],
    _s.dictationMode == DictationMode.holdToTalk ? 'Segurar' : 'Alternar',
    (v) async {
      await _s.setDictationMode(
        v == 'Segurar' ? DictationMode.holdToTalk : DictationMode.toggle,
      );
      await widget.dictation!.applySettings();
      if (mounted) setState(() {});
    },
  );

  Future<void> _changeDictationHotkey() async {
    final captured = await showDialog<Hotkey>(
      context: context,
      builder: (_) => _HotkeyCaptureDialog(current: _s.hotkey),
    );
    if (captured == null) return;
    await _s.setHotkey(captured);
    await widget.dictation!.applySettings();
    if (mounted) setState(() {});
  }

  Widget _recordNoteRow() {
    final status = widget.recordNoteHotkey.status;
    final enabled = _s.recordHotkeyEnabled;
    final sub = switch (status) {
      _ when !enabled => 'Desativado',
      RecordNoteHotkeyStatus(hasError: true) =>
        'Não foi possível registrar: ${status.error}',
      _ => 'Gravar nota de qualquer app',
    };
    return _SettingRow(
      label: 'Gravar nota',
      sub: sub,
      subColor: status.hasError && enabled ? RbTokens.destructive : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (enabled) ...[
            _Keys(keys: MacKeyCodes.symbols(_s.recordHotkey)),
            const SizedBox(width: 10),
            _PillButton(label: 'Alterar', onTap: _changeRecordHotkey),
            const SizedBox(width: 8),
          ],
          _Toggle(
            value: enabled,
            onChanged: (v) async {
              await _s.setRecordHotkeyEnabled(value: v);
              await widget.recordNoteHotkey.applySettings();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Future<void> _changeRecordHotkey() async {
    final captured = await showDialog<Hotkey>(
      context: context,
      builder: (_) => _HotkeyCaptureDialog(current: _s.recordHotkey),
    );
    if (captured == null) return;
    await _s.setRecordHotkey(captured);
    await widget.recordNoteHotkey.applySettings();
    if (mounted) setState(() {});
  }

  Widget _privacidade() => _Groups([
    _Group(
      rows: [
        _toggle(
          'Bloquear com Touch ID',
          'Pede o Touch ID ao voltar de tela bloqueada, sono ou protetor '
              'de tela. Cobre também o diário.',
          _s.touchIdLock,
          (v) => context.read<AppLockCubit>().setEnabled(enabled: v),
        ),
        _select(
          'Manter áudios originais',
          const ['Para sempre', '1 ano', '90 dias', '30 dias'],
          _s.retention,
          _s.setRetention,
        ),
        _toggle(
          'Apagar áudio após transcrever',
          'Mantém apenas o texto e o resumo',
          _s.deleteAudioAfter,
          (v) => _s.setDeleteAudioAfter(value: v),
        ),
        if (widget.noteKeyStore != null)
          _button(
            'Chave de recuperação',
            'Abra suas notas bloqueadas em outro Mac',
            'Gerenciar…',
            onTap: _openRecoveryKey,
          ),
      ],
    ),
    _Group(
      title: 'Seus dados',
      rows: [
        _button(
          'Exportar todas as notas',
          'Markdown + áudio, em um arquivo .zip',
          'Exportar',
        ),
        _button(
          'Apagar todos os dados',
          'Remove notas deste Mac e da nuvem',
          'Apagar…',
          destructive: true,
          onTap: _confirmEraseAllData,
        ),
      ],
    ),
    _Group(
      title: 'Diagnóstico',
      foot:
          'Os logs ajudam a investigar problemas. Não contêm o conteúdo das '
          'notas nem tokens.',
      rows: [
        _button(
          'Logs do aplicativo',
          'Abre ~/Library/Logs/RbNotes no Finder',
          'Abrir pasta',
          onTap: _openLogsFolder,
        ),
      ],
    ),
  ]);

  Future<void> _openRecoveryKey() async {
    final store = widget.noteKeyStore;
    if (store == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => RecoveryKeyDialog(
        keyStore: store,
        onKeyChanged: widget.onRecoveryKeyChanged,
      ),
    );
  }

  Future<void> _openAccountConsole() async {
    final uri = Uri.parse(
      'https://auth.rodolfodebonis.com.br/realms/rbnotes/account',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'open_account_console',
        category: 'settings',
      );
    }
  }

  Future<void> _openLogsFolder() async {
    try {
      final dir = Directory(AppPaths.logsDirPath);
      await dir.create(recursive: true);
      await launchUrl(Uri.file(dir.path));
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'open_logs_folder',
        category: 'settings',
      );
    }
  }

  Future<void> _openVocabularyEditor() async {
    await showDialog<void>(
      context: context,
      builder: (_) => VocabularyEditorDialog(repository: widget.vocabulary),
    );
    await _refreshVocabCount();
  }

  Future<void> _confirmEraseAllData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar todos os dados?'),
        content: const Text(
          'Isso remove todas as notas e os áudios deste Mac. '
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: RbTokens.destructive,
            ),
            child: const Text('Apagar tudo'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await widget.onEraseAllData();
    }
  }

  // ---------------- row builders ----------------

  Widget _toggle(
    String label,
    String? sub,
    bool value,
    ValueChanged<bool> onChanged,
  ) => _SettingRow(
    label: label,
    sub: sub,
    trailing: _Toggle(
      value: value,
      onChanged: (v) {
        onChanged(v);
        setState(() {});
      },
    ),
  );

  Widget _select(
    String label,
    List<String> options,
    String value,
    ValueChanged<String> onChanged,
  ) => _SettingRow(
    label: label,
    trailing: RbSelect<String>(
      value: value,
      options: options,
      onChanged: (v) {
        onChanged(v);
        setState(() {});
      },
    ),
  );

  Widget _micRow() {
    final names = _micDevices.isEmpty
        ? [_s.micName]
        : _micDevices.map((d) => d.name).toList();
    final value = names.contains(_s.micName) ? _s.micName : names.first;
    return _select('Microfone', names, value, (name) {
      final device = _micDevices.where((d) => d.name == name).firstOrNull;
      unawaited(_s.setMic(device?.id, name));
    });
  }

  Widget _segRow(
    String label,
    List<String> options,
    String value,
    ValueChanged<String> onChanged,
  ) => _SettingRow(
    label: label,
    trailing: _Segmented(
      options: options,
      value: value,
      onChanged: (v) {
        onChanged(v);
        setState(() {});
      },
    ),
  );

  Widget _keys(String label, List<String> keys) => _SettingRow(
    label: label,
    trailing: _Keys(keys: keys),
  );

  Widget _button(
    String label,
    String? sub,
    String action, {
    VoidCallback? onTap,
    bool destructive = false,
  }) => _SettingRow(
    label: label,
    sub: sub,
    trailing: _PillButton(
      label: action,
      onTap: onTap,
      destructive: destructive,
    ),
  );

  Widget _status(String label, String value) => _SettingRow(
    label: label,
    trailing: Text(
      value,
      style: context.bodyText(size: 12, color: context.rb.secondary(0.65)),
    ),
  );

  Widget _syncStatusRow(SyncService sync) => StreamBuilder<SyncStatus>(
    stream: sync.status,
    initialData: sync.current,
    builder: (context, snap) {
      final status = snap.data ?? const SyncStatus();
      final pendingSuffix = status.hasPending
          ? ' · ${status.pendingCount} '
                '${status.pendingCount == 1 ? 'pendente' : 'pendentes'}'
          : '';
      final text = switch (status.phase) {
        SyncPhase.syncing => 'Sincronizando…',
        SyncPhase.offline => 'Sem conexão$pendingSuffix',
        SyncPhase.error =>
          '${status.message ?? 'Falha ao sincronizar'}$pendingSuffix',
        SyncPhase.disabled => 'Desligado',
        SyncPhase.idle =>
          (status.lastSyncAt == null
                  ? 'Nunca sincronizado'
                  : _ago(status.lastSyncAt!)) +
              pendingSuffix,
      };
      return _SettingRow(
        label: 'Última sincronização',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: context.bodyText(
                size: 12,
                color: status.hasError
                    ? const Color(0xFFD70015)
                    : context.rb.secondary(0.65),
              ),
            ),
            const SizedBox(width: 10),
            _PillButton(
              label: 'Sincronizar agora',
              onTap: status.isSyncing
                  ? null
                  : () => unawaited(sync.syncNow(manual: true)),
            ),
          ],
        ),
      );
    },
  );

  static String _ago(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'agora mesmo';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'há ${diff.inHours} h';
    return 'há ${diff.inDays} d';
  }

  Widget _modelRow(WhisperModel model) {
    final info = whisperModelInfo[model]!;
    final has = _downloaded.contains(model);
    final selected = _s.model == model;
    final progress = _downloading[model];
    return _SettingRow(
      leading: _Radio(selected: selected && has),
      label: info.$1,
      labelDim: !has,
      labelBold: selected,
      sub: '${info.$2} · ${info.$3}',
      onTap: has ? () => setState(() => _s.setModel(model)) : null,
      trailing: _modelTrailing(
        model,
        has: has,
        selected: selected,
        progress: progress,
      ),
    );
  }

  Widget _modelTrailing(
    WhisperModel model, {
    required bool has,
    required bool selected,
    required double? progress,
  }) {
    final rb = context.rb;
    if (progress != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 80,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: rb.controlFill,
                valueColor: AlwaysStoppedAnimation(rb.accent),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(progress * 100).round()}%',
            style: context.bodyText(size: 11, color: rb.secondary(0.65)),
          ),
        ],
      );
    }
    if (!has) {
      return GestureDetector(
        onTap: () => _download(model),
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: rb.accentWash(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Baixar',
            style: context.bodyText(
              size: 12,
              weight: FontWeight.w600,
              color: rb.accent,
            ),
          ),
        ),
      );
    }
    return Text(
      selected ? 'Em uso' : 'Baixado',
      style: context.bodyText(
        size: 12,
        color: selected ? rb.accent : rb.secondary(0.55),
      ),
    );
  }

  Widget _profileRow() {
    final rb = context.rb;
    return _SettingRow(
      leading: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(color: rb.ink, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(
          widget.userInitials,
          style: context.bodyText(
            size: 16,
            weight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      label: widget.userName,
      labelBold: true,
      labelSize: 15,
      sub: widget.userEmail,
      trailing: _PillButton(label: 'Editar perfil', onTap: _openAccountConsole),
    );
  }

  // ---------------- helpers ----------------

  String _appearanceLabel(ThemeMode m) => switch (m) {
    ThemeMode.light => 'Claro',
    ThemeMode.dark => 'Escuro',
    ThemeMode.system => 'Sistema',
  };
  ThemeMode _themeFor(String v) => switch (v) {
    'Claro' => ThemeMode.light,
    'Escuro' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
  String _folderLabel(String id) => switch (id) {
    'trabalho' => 'Trabalho',
    'pessoal' => 'Pessoal',
    'estudos' => 'Estudos',
    _ => 'Ideias',
  };
  String _folderId(String label) => switch (label) {
    'Trabalho' => 'trabalho',
    'Pessoal' => 'pessoal',
    'Estudos' => 'estudos',
    _ => 'ideias',
  };
  String _styleLabel(SummaryStyle s) => switch (s) {
    SummaryStyle.objetivo => 'Objetivo',
    SummaryStyle.detalhado => 'Detalhado',
    SummaryStyle.topicos => 'Em tópicos',
  };
  SummaryStyle _style(String v) => switch (v) {
    'Detalhado' => SummaryStyle.detalhado,
    'Em tópicos' => SummaryStyle.topicos,
    _ => SummaryStyle.objetivo,
  };
  String _lengthLabel(SummaryLength l) => switch (l) {
    SummaryLength.curto => 'Curto',
    SummaryLength.medio => 'Médio',
    SummaryLength.longo => 'Longo',
  };
  SummaryLength _length(String v) => switch (v) {
    'Curto' => SummaryLength.curto,
    'Longo' => SummaryLength.longo,
    _ => SummaryLength.medio,
  };
}

// ============ widgets ============

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.tab,
    required this.onTab,
    required this.onClose,
  });

  final SettingsTab tab;
  final ValueChanged<SettingsTab> onTab;
  final VoidCallback onClose;

  static const _defs = <(SettingsTab, String, IconData)>[
    (SettingsTab.geral, 'Geral', Icons.settings_outlined),
    (SettingsTab.gravacao, 'Gravação', Icons.mic_none_outlined),
    (SettingsTab.transcricao, 'Transcrição', Icons.graphic_eq),
    (SettingsTab.ia, 'Inteligência', Icons.auto_awesome_outlined),
    (SettingsTab.conta, 'Conta', Icons.person_outline),
    (SettingsTab.uso, 'Uso', Icons.bar_chart_outlined),
    (SettingsTab.atalhos, 'Atalhos', Icons.keyboard_outlined),
    (SettingsTab.privacidade, 'Privacidade', Icons.lock_outline),
  ];

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final title = _defs.firstWhere((d) => d.$1 == tab).$2;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: rb.side,
        border: Border(
          bottom: BorderSide(color: rb.onSurface(0.1), width: 0.5),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 16,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TrafficLights(onClose: onClose, interactive: false),
                ),
                Text(
                  title,
                  style: context.bodyText(size: 13, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final d in _defs)
                GestureDetector(
                  onTap: () => onTab(d.$1),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 78,
                    height: 52,
                    decoration: BoxDecoration(
                      color: tab == d.$1
                          ? rb.onSurface(0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          d.$3,
                          size: 20,
                          color: tab == d.$1 ? rb.accent : rb.secondary(0.8),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          d.$2,
                          style: context.bodyText(
                            size: 11,
                            weight: FontWeight.w500,
                            color: tab == d.$1 ? rb.accent : rb.secondary(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Groups extends StatelessWidget {
  const _Groups(this.groups);
  final List<_Group> groups;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0) const SizedBox(height: 22),
          groups[i],
        ],
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.rows, this.title, this.foot});
  final String? title;
  final String? foot;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 7),
            child: Text(
              title!,
              style: context.bodyText(
                size: 12,
                weight: FontWeight.w600,
                color: rb.secondary(0.65),
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: rb.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: rb.onSurface(0.09), width: 0.5),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                Container(
                  decoration: BoxDecoration(
                    border: i == 0
                        ? null
                        : Border(
                            top: BorderSide(
                              color: rb.onSurface(0.08),
                              width: 0.5,
                            ),
                          ),
                  ),
                  child: rows[i],
                ),
            ],
          ),
        ),
        if (foot != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 7, 4, 0),
            child: Text(
              foot!,
              style: context.bodyText(
                size: 11.5,
                height: 1.45,
                color: rb.secondary(0.6),
              ),
            ),
          ),
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    this.sub,
    this.subColor,
    this.leading,
    this.trailing,
    this.onTap,
    this.labelDim = false,
    this.labelBold = false,
    this.labelSize = 13,
  });

  final String label;
  final String? sub;
  final Color? subColor;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool labelDim;
  final bool labelBold;
  final double labelSize;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: context.bodyText(
                      size: labelSize,
                      weight: labelBold ? FontWeight.w600 : FontWeight.w400,
                      color: labelDim ? rb.secondary(0.55) : rb.text,
                    ),
                  ),
                  if (sub != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        sub!,
                        style: context.bodyText(
                          size: 11.5,
                          height: 1.4,
                          color: subColor ?? rb.secondary(0.62),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 36,
        height: 20,
        decoration: BoxDecoration(
          color: value ? rb.accent : const Color(0x3D787880),
          borderRadius: BorderRadius.circular(10),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(2),
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: rb.controlFill,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in options)
            GestureDetector(
              onTap: () => onChanged(o),
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value == o ? rb.seg : Colors.transparent,
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: value == o
                      ? [
                          BoxShadow(
                            color: rb.onSurface(0.12),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  o,
                  style: context.bodyText(size: 12, weight: FontWeight.w500),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Keys extends StatelessWidget {
  const _Keys({required this.keys});
  final List<String> keys;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final k in keys)
          Container(
            margin: const EdgeInsets.only(left: 4),
            constraints: const BoxConstraints(minWidth: 24),
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: rb.fill,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: rb.onSurface(0.14), width: 0.5),
            ),
            child: Text(
              k,
              style: context.bodyText(size: 12, weight: FontWeight.w500),
            ),
          ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    this.onTap,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: rb.controlFill,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: context.bodyText(
            size: 12.5,
            weight: FontWeight.w500,
            color: destructive ? RbTokens.destructive : rb.text,
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: selected ? rb.accent : Colors.transparent,
        shape: BoxShape.circle,
        border: selected
            ? null
            : Border.all(color: rb.secondary(0.3), width: 1.5),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );
  }
}

/// Captura um novo atalho global: pressione a combinação desejada (ao menos um
/// modificador + uma tecla). Retorna o [Hotkey] no `pop`, ou null se cancelado.
class _HotkeyCaptureDialog extends StatefulWidget {
  const _HotkeyCaptureDialog({required this.current});
  final Hotkey current;

  @override
  State<_HotkeyCaptureDialog> createState() => _HotkeyCaptureDialogState();
}

class _HotkeyCaptureDialogState extends State<_HotkeyCaptureDialog> {
  final _focusNode = FocusNode();
  String? _hint;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final key = event.logicalKey;
    if (MacKeyCodes.isModifier(key)) return KeyEventResult.handled;

    final keyCode = MacKeyCodes.fromLogicalKey(key);
    if (keyCode == null) {
      setState(() => _hint = 'Tecla não suportada. Tente outra.');
      return KeyEventResult.handled;
    }
    final hw = HardwareKeyboard.instance;
    final modifiers = <HotkeyModifier>{
      if (hw.isMetaPressed) HotkeyModifier.command,
      if (hw.isAltPressed) HotkeyModifier.option,
      if (hw.isControlPressed) HotkeyModifier.control,
      if (hw.isShiftPressed) HotkeyModifier.shift,
    };
    if (modifiers.isEmpty) {
      setState(
        () => _hint = 'Use ao menos um modificador (⌘ ⌥ ⌃ ⇧).',
      );
      return KeyEventResult.handled;
    }
    Navigator.of(context).pop(Hotkey(keyCode: keyCode, modifiers: modifiers));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: AlertDialog(
        backgroundColor: rb.card,
        title: const Text('Definir atalho'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Pressione a nova combinação',
              style: context.bodyText(size: 12.5, color: rb.secondary(0.7)),
            ),
            const SizedBox(height: 14),
            _Keys(keys: MacKeyCodes.symbols(widget.current)),
            if (_hint != null) ...[
              const SizedBox(height: 12),
              Text(
                _hint!,
                textAlign: TextAlign.center,
                style: context.bodyText(
                  size: 11.5,
                  color: RbTokens.destructive,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }
}
