import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/settings/data/system_settings.dart';
import 'package:rbnotes/native/rb_native.dart';

void main() {
  group('SystemSettingsOpener', () {
    test('urlFor aponta para o painel de Privacidade certo', () {
      expect(
        SystemSettingsOpener.urlFor(RbPermission.microphone),
        contains('Privacy_Microphone'),
      );
      expect(
        SystemSettingsOpener.urlFor(RbPermission.screenRecording),
        contains('Privacy_ScreenCapture'),
      );
      expect(
        SystemSettingsOpener.urlFor(RbPermission.accessibility),
        contains('Privacy_Accessibility'),
      );
      expect(
        SystemSettingsOpener.urlFor(RbPermission.microphone),
        startsWith('x-apple.systempreferences:'),
      );
    });

    test('openPrivacyPane abre a URL do painel', () async {
      final opened = <Uri>[];
      final opener = SystemSettingsOpener(
        launcher: (uri) async {
          opened.add(uri);
          return true;
        },
      );
      await opener.openPrivacyPane(RbPermission.screenRecording);
      expect(opened.single.toString(), contains('Privacy_ScreenCapture'));
    });

    test('falha ao abrir é engolida (não propaga)', () async {
      final opener = SystemSettingsOpener(
        launcher: (_) async => throw Exception('no handler'),
      );
      await expectLater(
        opener.openPrivacyPane(RbPermission.microphone),
        completes,
      );
    });
  });
}
