import 'package:dart_onnx/dart_onnx.dart';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:test/test.dart';

import '../hook/build.dart' as build_hook;

/// The package contract this fork did not have before: a consumer gets a real
/// ORT runtime without Homebrew, PATH, or another plugin happening to bundle
/// one. Running this test itself executes the build hook, resolves the bundled
/// code asset, and asks that runtime for its version.
void main() {
  test('the native-assets hook supplies ONNX Runtime', () {
    final env = DartONNX(loggingLevel: DartONNXLoggingLevel.warning);
    addTearDown(env.dispose);

    expect(env.ortVersion, startsWith('1.27.'));
  });

  test('external runtime mode emits no competing ONNX Runtime asset', () async {
    final userDefines = PackageUserDefines(
      workspacePubspec: PackageUserDefinesSource(
        defines: const {'runtime': 'external'},
        basePath: Uri.directory('.'),
      ),
    );

    await testCodeBuildHook(
      mainMethod: build_hook.main,
      targetOS: OS.linux,
      targetArchitecture: Architecture.x64,
      userDefines: userDefines,
      check: (input, output) {
        expect(output.assets.code, isEmpty);
      },
    );
  });
}
