import 'dart:io';

import 'package:fast_build_runner/src/cli.dart';

Future<void> main(List<String> args) async {
  final exitCode = await FastBuildRunnerCli().run(args);
  if (exitCode != 0) {
    stderr.writeln('fast_build_runner exited with code $exitCode.');
  }
  exit(exitCode);
}

