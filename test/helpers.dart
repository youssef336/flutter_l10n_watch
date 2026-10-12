import 'dart:io';

import 'package:flutter_l10n_watch/flutter_l10n_watch.dart';
import 'package:path/path.dart' as p;

String fixture(String name) => p.join('test', 'fixtures', name);

/// Copies a fixture to a fresh temp folder (deleted by the caller's tearDown).
Directory copyFixture(String name) {
  final target = Directory.systemTemp.createTempSync('l10n_watch_');
  _copy(Directory(fixture(name)), target);
  return target;
}

void _copy(Directory from, Directory to) {
  for (final entity in from.listSync(recursive: true)) {
    final relative = p.relative(entity.path, from: from.path);
    final destination = p.join(to.path, relative);
    if (entity is Directory) {
      Directory(destination).createSync(recursive: true);
    } else if (entity is File) {
      File(destination).parent.createSync(recursive: true);
      entity.copySync(destination);
    }
  }
}

/// Writes [files] (relative path → content) into a new temp project.
Directory tempProject(Map<String, String> files) {
  final root = Directory.systemTemp.createTempSync('l10n_watch_');
  files.forEach((path, content) {
    File(p.join(root.path, path))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  });
  return root;
}

CheckResult check(String root, {Config? config, Set<String>? only}) =>
    runChecks(loadProject(root, config ?? Config.load(p.join(root, configFileName))), only: only);

List<Finding> of(CheckResult result, String check) =>
    result.findings.where((f) => f.check == check).toList();

List<String> keysOf(CheckResult result, String check) =>
    of(result, check).map((f) => '${f.locale ?? ''}:${f.key ?? ''}').toList();
