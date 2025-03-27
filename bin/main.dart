import 'dart:io';

import 'package:http/http.dart' as http;

import 'console_color.dart';

const version = 'DEV';
const repository = 'https://github.com/ygimenez/build_script';
final cli = http.Client();

void main(List<String> args) async {
  final old = File('${Platform.script.path}.old');
  if (await old.exists()) {
    await old.delete();
  }

  info('BuildScript Version $version');

  info('Fetching latest version...');
  final res = await cli.send(http.Request('HEAD', Uri.parse('$repository/releases/latest'))..followRedirects = false);
  if (res.headers.containsKey("location")) {
    final latest = res.headers["location"]!.split("/").last;
    info(latest, true);

    if (version != latest) {
      File exe = File.fromUri(Platform.script);
      await exe.rename('${exe.path}.old');

      final res = await http.get(Uri.parse('$repository/releases/download/$latest/build_script.exe'));
      exe = await File(exe.path).writeAsBytes(res.bodyBytes, flush: true);

      await Process.start(exe.path, args, mode: ProcessStartMode.inheritStdio);
      exit(0);
    }
  } else {

  }

  info('Continue');
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