import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:rbnotes/app/accent_cubit.dart';
import 'package:rbnotes/app/shell/tray_controller.dart';
import 'package:rbnotes/app/theme_mode_cubit.dart';
import 'package:rbnotes/core/di/injector.dart';
import 'package:rbnotes/core/theme/rbnotes_theme.dart';
import 'package:rbnotes/core/windowing/settings_window_manager.dart';
import 'package:rbnotes/features/auth/data/auth_service.dart';
import 'package:rbnotes/features/dictation/data/dictation_service.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/recording/data/meeting_detection_service.dart';
import 'package:rbnotes/features/security/presentation/app_lock_cubit.dart';
import 'package:rbnotes/features/security/presentation/lock_screen.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/settings/presentation/settings_actions.dart';
import 'package:rbnotes/features/settings/presentation/settings_modal.dart';
import 'package:rbnotes/features/sync/data/audio_upload_queue.dart';
import 'package:rbnotes/features/sync/data/sync_crypto.dart';
import 'package:rbnotes/features/sync/data/sync_service.dart';
import 'package:rbnotes/notifications/notification_coordinator.dart';

/// Root widget rendered into the native Settings window (a separate native
/// window). It is the same isolate as the main
/// window, so it shares the live [ThemeModeCubit] / [AccentCubit] /
/// [AppLockCubit] singletons — changing the theme or accent here updates both
/// windows instantly. Its own [MaterialApp] gives it a [Navigator] so every
/// dialog, picker, Touch ID prompt and chart opens inside this window.
class SettingsWindowApp extends StatelessWidget {
  const SettingsWindowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: di<ThemeModeCubit>()),
        BlocProvider.value(value: di<AccentCubit>()),
        BlocProvider.value(value: di<AppLockCubit>()),
      ],
      child: BlocBuilder<ThemeModeCubit, ThemeMode>(
        builder: (context, mode) => BlocBuilder<AccentCubit, Color>(
          builder: (context, accent) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RbNotesTheme.light(accent),
            darkTheme: RbNotesTheme.dark(accent),
            themeMode: mode,
            locale: const Locale('pt', 'BR'),
            supportedLocales: const [Locale('pt', 'BR')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const _SettingsWindowHome(),
          ),
        ),
      ),
    );
  }
}

class _SettingsWindowHome extends StatelessWidget {
  const _SettingsWindowHome();

  @override
  Widget build(BuildContext context) {
    final manager = di<SettingsWindowManager>();
    return CallbackShortcuts(
      bindings: {
        // ⌘W closes the window (same as the red traffic light).
        const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
            manager.close,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: BlocBuilder<AppLockCubit, AppLockState>(
            builder: (context, lock) => Stack(
              children: [
                // While Touch ID locks the app, the Settings window is covered
                // too (and cannot receive focus/shortcuts), like the main one.
                ExcludeFocus(
                  excluding: lock.locked,
                  child: const _SettingsBody(),
                ),
                if (lock.locked) const LockScreen(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsBody extends StatelessWidget {
  const _SettingsBody();

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 2600),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final manager = di<SettingsWindowManager>();
    final user = di<AuthService>().currentUser;
    return SettingsModal(
      store: di<SettingsStore>(),
      native: di(),
      vocabulary: di(),
      recordNoteHotkey: di(),
      aiUsageClient: di(),
      dictation: di.isRegistered<DictationService>()
          ? di<DictationService>()
          : null,
      meetingDetection: di.isRegistered<MeetingDetectionService>()
          ? di<MeetingDetectionService>()
          : null,
      noteKeyStore: di(),
      onMenuBarChanged: (enabled) {
        if (di.isRegistered<TrayController>()) {
          unawaited(di<TrayController>().setVisible(enabled: enabled));
        }
      },
      onRecoveryKeyChanged: () {
        if (di.isRegistered<SyncCrypto>()) di<SyncCrypto>().invalidate();
      },
      notifier: di(),
      onNotificationsChanged: () =>
          unawaited(di<NotificationCoordinator>().rescheduleAll()),
      userName: user?.name ?? 'Você',
      userEmail: user?.email ?? '',
      userInitials: user?.initials ?? 'V',
      sync: di.isRegistered<SyncService>() ? di<SyncService>() : null,
      audioQueue: di.isRegistered<AudioUploadQueue>()
          ? di<AudioUploadQueue>()
          : null,
      notes: di<NoteRepository>(),
      onTitleChanged: manager.setTitle,
      onClose: manager.close,
      onLogout: ({required wipe}) async {
        manager.close();
        if (wipe) await wipeLocalData();
        await di<AuthService>().signOut();
      },
      onEraseAllData: () => eraseAllData(
        context,
        onToast: (m) => _toast(context, m),
        closeSettings: manager.close,
      ),
      onExportAll: () =>
          exportAllNotes(context, onToast: (m) => _toast(context, m)),
    );
  }
}
