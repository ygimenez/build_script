import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';

import 'console_color.dart';
import 'templates.dart';

const version = 'DEV';
const repository = 'https://github.com/ygimenez/build_script';
const blobs = 'https://raw.githubusercontent.com/ygimenez/build_script/refs/heads/master';
const isRelease = version != 'DEV';
const chocoInstall =
    "Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))";
final cli = http.Client();

void main(List<String> args) async {
  final isAdmin = bool.parse(
    await Process.run('powershell', [
      '([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)',
    ]).then((p) => (p.stdout as String).toLowerCase().trim()),
  );

  if (!isAdmin) {
    error('This program requires elevation');
    exit(1);
  }

  final pubspec = File('pubspec.yaml');
  if (await pubspec.exists()) {
    final info = loadYaml(await pubspec.readAsString());
    if (info['dependencies']?['flutter']?['sdk'] != 'flutter') {
      error('Project is not a flutter project');
      exit(1);
    }
  } else {
    error('Pubspec not found, this program must be placed at project root');
    exit(1);
  }

  if (args.isEmpty) {
    info('App name: ');
    final appname = stdin.readLineSync()?.replaceAll(' ', '').trim();

    if (appname == null) {
      error('An app name is required');
      info(
        '''
        Usage:
        - ${Platform.script.pathSegments.last} ${Green('[App name]')}
        '''
            .replaceAll(RegExp(r'^\s+', multiLine: true), ''),
      );

      exit(1);
    }

    args.add(appname);
  }

  info('BuildScript Version $version');

  info('---------------------------------------------------');

  info('Checking for updates...');
  final res = await cli.send(http.Request('HEAD', Uri.parse('$repository/releases/latest'))..followRedirects = false);
  if (res.headers.containsKey('location')) {
    final latest = res.headers['location']!.split('/').last;
    info('available', true);

    if (version != latest) {
      File exe = File.fromUri(Platform.script);
      if (isRelease) {
        await exe.rename('${exe.path}.old');
      }

      info('Downloading new version');
      final resExe = await http.get(Uri.parse('$repository/releases/download/$latest/build_script.exe'));
      info(Green('Download complete'));

      final hash = md5.convert(resExe.bodyBytes).toString().toUpperCase();
      {
        final resHash = await http.get(Uri.parse('$repository/releases/download/$latest/checksum.md5'));
        if (hash == resHash.body.trim()) {
          if (isRelease) {
            info('Restarting program...');
            exe = await File(exe.path).writeAsBytes(resExe.bodyBytes, flush: true);
            await Process.start('del ${exe.path}.old && start "" "${exe.path}"', args, runInShell: true);
            exit(0);
          }
        } else {
          warn('Checksum mismatch, aborting update');
        }
      }
    } else {
      info('up-to-date', true);
    }
  } else {
    warn('Unable to retrieve latest version');
  }

  info('---------------------------------------------------');

  info('Checking dependencies');
  final deps = {
    'Chocolatey': () async => await exec('choco', args: ['--version'], installScript: chocoInstall, writeOutput: false),
    'Dart SDK': () async => await exec('dart', args: ['--version'], packageId: 'dart-sdk', writeOutput: false),
    'Flutter SDK': () async => await exec('flutter', args: ['--version'], packageId: 'flutter', writeOutput: false),
    'Inno Setup': () async => await exec('iscc', args: ['/?'], path: r'C:\Program Files (x86)\Inno Setup 6\', packageId: 'innosetup', writeOutput: false),
    'WinRAR': () async => await exec('rar', args: ['-iver'], path: r'C:\Program Files\WinRAR\', packageId: 'winrar', writeOutput: false),
  };

  for (final e in deps.entries) {
    info('${e.key}: ');
    await e.value();
    info(Cyan('OK'), true);
  }

  info('---------------------------------------------------');

  final gitignore = File('.gitignore');
  if (await gitignore.exists()) {
    final lines = await gitignore.readAsLines();
    if (!lines.any((l) => l == '# Added by build_script')) {
      lines.addAll([
        '',
        '# Added by build_script',
        'output/',
        './*.iss',
      ]);

      await gitignore.writeAsString(lines.join('\n'));
      info('Added paths to .gitignore');
    }
  }

  await exec('flutter', args: ['clean']);

  final output = Directory('./output');
  if (!await output.exists()) {
    await output.create();
  } else {
    await for (final f in output.list()) {
      await f.delete();
    }
  }

  final appName = args.first;
  if (await Directory('./windows').exists()) {
    info('--------------------- WINDOWS ---------------------');

    /* Remake Installer */
    {
      final installer = File('Installer.iss');
      final nameParts = appName.split(RegExp(r'(?<=.)(?=[A-Z][a-z])'));
      final uuid = Uuid();

      final props = {
        'TITLE': nameParts.join(' '),
        'VERSION': version,
        'EXENAME': nameParts.join(' ').toLowerCase(),
        'GUID': uuid.v5(Namespace.url.value, 'bels.com.br/$appName'),
        'NAME': appName,
      };

      await installer.writeAsString(kInstaller.replaceAllMapped(RegExp(r'{{(\w+)}}'), (match) => props[match[1]] ?? ""));
    }

    /* Remake CodeDependencies */
    {
      final codeDeps = File('CodeDependencies.iss');
      await codeDeps.writeAsString(kCodeDependencies);
    }

    final icon = File('asset/installer.ico');
    if (!await icon.exists()) {
      warn('Installer icon not found, using fallback icon (path: ./asset/installer.ico)');
      final res = await http.get(Uri.parse('$blobs/fallback/installer.ico'));
      await icon.writeAsBytes(res.bodyBytes);
    }

    await exec('flutter', args: ['build', 'windows']) &&
        await exec('iscc', args: ['Installer.iss'], path: r'C:\Program Files (x86)\Inno Setup 6\') &&
        await exec('rar', args: ['a', '-ep1', join(output.path, 'Windows_${appName}_$version.rar'), join(output.path, '${appName}_setup.exe')], path: r'C:\Program Files\WinRAR\');
  }

  if (await Directory('./android').exists()) {
    info('--------------------- ANDROID ---------------------');

    final built = await exec('flutter', args: ['build', 'apk']);
    if (built) {
      final apk = File('build/app/outputs/flutter-apk/app-release.apk');
      if (await apk.exists()) {
        await apk.rename('$appName.apk');
        await exec('rar', args: ['a', '-ep1', join(output.path, 'Android_${appName}_$version.rar'), apk.path], path: r'C:\Program Files\WinRAR\');
      }
    }
  }

  if (await Directory('./linux').exists()) {
    info('---------------------  LINUX  ---------------------');
    // NOT IMPLEMENTED
  }

  if (await Directory('./web').exists()) {
    info('---------------------   WEB   ---------------------');

    final dir = Directory('build/web');
    if (await dir.exists()) {
      await exec('flutter', args: ['build', 'web']) &&
          await exec('rar', args: ['a', '-r', '-ep1', join(output.path, 'Web_${appName}_$version.rar'), join(dir.path, '*')], path: r'C:\Program Files\WinRAR\');
    }
  }

  exit(0);
}

Future<bool> exec(String program, {String path = '', List<String> args = const [], String? packageId, String? installScript, bool writeOutput = true}) async {
  try {
    if (writeOutput) {
      info('');
      return await Process.start('$path$program', args, runInShell: true, mode: ProcessStartMode.inheritStdio).then((p) => p.exitCode) == 0;
    }

    return await Process.run('$path$program', args, runInShell: true).then((p) => p.exitCode) == 0;
  } on ProcessException {
    if (packageId != null || installScript != null) {
      info("Process '$program' not found, installing...\n");

      bool installed = false;
      if (packageId != null) {
        installed = await Process.start('choco', ['install', packageId, '-y'], mode: ProcessStartMode.inheritStdio).then((p) => p.exitCode) == 0;
      } else if (installScript != null) {
        final prog = installScript.split(' ').first;
        final args = installScript.replaceFirst(prog, '').trim();
        installed = await Process.start(prog, [args], mode: ProcessStartMode.inheritStdio).then((p) => p.exitCode) == 0;
      }

      if (!installed) {
        error("Failed to install dependency '$program', aborting execution");
        exit(1);
      } else {
        info("Installed '$program' successfully");
        return exec(program, path: path, args: args, packageId: packageId, installScript: installScript, writeOutput: writeOutput);
      }
    }

    error("Process '$program' not found, please install before proceeding");
    exit(1);
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
