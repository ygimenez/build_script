import 'dart:io';

import 'console_color.dart';

void main(List<String> args) async {
  exec('git', ['-v'], 'Git.Git');
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

void info(text) {
  print(White(text.toString()));
}

void warn(text) {
  print(Yellow(text.toString()));
}

void error(text) {
  print(Red(text.toString()));
}

void log(List<ConsoleColor> data) {
  print(data.map((e) => e.toString()).join(' '));
}