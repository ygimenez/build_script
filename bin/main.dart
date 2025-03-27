import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'console_color.dart';

const version = 'DEV';
const repository = 'https://github.com/ygimenez/build_script';
const isRelease = version != 'DEV';
final cli = http.Client();

void main(List<String> args) async {
  info('BuildScript Version $version');

  info('Fetching latest version...');
  final res = await cli.send(http.Request('HEAD', Uri.parse('$repository/releases/latest'))..followRedirects = false);
  if (res.headers.containsKey("location")) {
    final latest = res.headers["location"]!.split("/").last;
    info(latest, true);

    if (version != latest) {
      File exe = File.fromUri(Platform.script);
      if (isRelease) {
        await exe.rename('${exe.path}.old');
      }

      final resExe = await http.get(Uri.parse('$repository/releases/download/$latest/build_script.exe'));
      final hash = md5.convert(resExe.bodyBytes).toString().toUpperCase();
      {
        final resHash = await http.get(Uri.parse('$repository/releases/download/$latest/checksum.md5'));
        if (hash == resHash.body) {
          if (isRelease) {
            exe = await File(exe.path).writeAsBytes(resExe.bodyBytes, flush: true);
            await Process.start('del ${exe.path}.old && start ${exe.path}', [], runInShell: true);
            exit(0);
          }
        }
      }
    }
  } else {

  }

  // exec('git', [''], 'Git.Git');
  exit(0);
}

bool exec(String program, [List<String> args = const [], String? wingetId]) {
  try {
    return Process.runSync(program, args).exitCode == 0;
  } on ProcessException {
    if (wingetId == null) {
      error("Process '$program' not found, please install before proceeding");
      exit(1);
    } else {
      info("Process '$program' not found, installing...");
      if (!exec('winget', ['install', '-e', '--id $wingetId'])) {
        error("Failed to install dependency with ID '$wingetId', aborting execution");
        exit(1);
      }

      return exec(program, args, wingetId);
    }
  }
}

void info(content, [bool inline = false]) {
  log(Default(content), inline);
}

void warn(content, [bool inline = false]) {
  log(Yellow(content), inline);
}

void error(content, [bool inline = false]) {
  log(Red(content), inline);
}

void log(ConsoleColor content, [bool inline = false]) {
  stdout.write('${inline ? '' : '\n'}$content');
}