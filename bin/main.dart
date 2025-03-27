import 'dart:io';

import 'package:http/http.dart' as http;

import 'console_color.dart';
import 'package:yaml/yaml.dart';

const repository = 'https://github.com/ygimenez/Pagination-Utils/releases/latest';
final cli = http.Client();

void main(List<String> args) async {
  final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync());
  final version = pubspec['version'];
  info('BuildScript Version $version');

  info('Fetching latest version...');
  final res = await cli.send(http.Request('HEAD', Uri.parse(repository))..followRedirects = false);
  if (res.headers.containsKey("location")) {
    final latest = res.headers["location"]!.split("/").last;
    info(latest, true);

    if (version != latest) {

    }
  } else {

  }

  // exec('git', [''], 'Git.Git');
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