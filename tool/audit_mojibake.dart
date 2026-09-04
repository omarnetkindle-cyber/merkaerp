import 'dart:convert';
import 'dart:io';

final _marker = RegExp(r'Ã|Â|â|ð|ƒ|�');

int _score(String value) => _marker.allMatches(value).length;

String _repairLine(String line) {
  var current = line;
  for (var attempt = 0; attempt < 4; attempt++) {
    if (_score(current) == 0) break;
    try {
      final candidate = utf8.decode(latin1.encode(current));
      if (_score(candidate) >= _score(current)) break;
      current = candidate;
    } on FormatException {
      break;
    }
  }
  return current;
}

void main(List<String> args) {
  final fix = args.contains('--fix');
  final files =
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  var affectedFiles = 0;
  var affectedLines = 0;
  var changedLines = 0;
  for (final file in files) {
    final original = file.readAsStringSync();
    final lines = original.split('\n');
    final repaired = <String>[];
    var fileAffected = false;
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final fixed = _repairLine(line);
      if (_marker.hasMatch(line)) {
        fileAffected = true;
        affectedLines++;
        if (fixed != line) changedLines++;
        stdout.writeln('${file.path}:${index + 1}: $line');
        if (fixed != line) stdout.writeln('  -> $fixed');
      }
      repaired.add(fixed);
    }
    if (fileAffected) {
      affectedFiles++;
      if (fix && repaired.join('\n') != original) {
        file.writeAsStringSync(repaired.join('\n'));
      }
    }
  }

  stdout.writeln(
    'SUMMARY files=$affectedFiles lines=$affectedLines changed=$changedLines fix=$fix',
  );
}
