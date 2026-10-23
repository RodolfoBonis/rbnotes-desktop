// Integration test exercising the real native channel on a macOS host.
//
// Run with: flutter test integration_test -d macos
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rbnotes_native/rbnotes_native.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final RbNative native = MethodChannelRbNative();

  testWidgets('permissionStatus returns a value for each permission', (
    tester,
  ) async {
    for (final permission in RbPermission.values) {
      final status = await native.permissionStatus(permission);
      expect(PermissionStatus.values, contains(status));
    }
  });

  testWidgets('modelState reports a boolean downloaded flag', (tester) async {
    final state = await native.modelState(WhisperModel.smallQ5);
    expect(state.downloaded, isA<bool>());
  });
}
