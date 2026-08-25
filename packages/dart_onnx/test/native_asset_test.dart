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

  test('external platforms emit no competing ONNX Runtime asset', () async {
    final userDefines = PackageUserDefines(
      workspacePubspec: PackageUserDefinesSource(
        defines: const {
          'external_platforms': ['android', 'linux', 'windows'],
        },
        basePath: Uri.directory('.'),
      ),
    );

    for (final (os, architecture) in [
      (OS.android, Architecture.arm64),
      (OS.linux, Architecture.x64),
      (OS.windows, Architecture.x64),
    ]) {
      await testCodeBuildHook(
        mainMethod: build_hook.main,
        targetOS: os,
        targetArchitecture: architecture,
        userDefines: userDefines,
        check: (input, output) {
          expect(
            output.assets.code,
            isEmpty,
            reason: '${os.name}-$architecture',
          );
        },
      );
    }
  });

  test('macOS keeps its bundled ORT when Sherpa hides OrtGetApiBase', () async {
    final userDefines = PackageUserDefines(
      workspacePubspec: PackageUserDefinesSource(
        defines: const {
          'external_platforms': ['android', 'linux', 'windows'],
        },
        basePath: Uri.directory('.'),
      ),
    );

    await testCodeBuildHook(
      mainMethod: build_hook.main,
      targetOS: OS.macOS,
      targetArchitecture: Architecture.arm64,
      userDefines: userDefines,
      check: (input, output) {
        expect(output.assets.code, hasLength(1));
      },
    );
  });

  test('iOS emits no asset because the app supplies its framework', () async {
    await testCodeBuildHook(
      mainMethod: build_hook.main,
      targetOS: OS.iOS,
      targetArchitecture: Architecture.arm64,
      check: (input, output) {
        expect(output.assets.code, isEmpty);
      },
    );
  });
}
