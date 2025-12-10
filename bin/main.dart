import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';

import 'console_color.dart';
import 'templates.dart';

const kVersion = 'DEV';
const kRepository = 'https://github.com/ygimenez/build_script';
const kBlobs = 'https://raw.githubusercontent.com/ygimenez/build_script/refs/heads/master';
const kIsRelease = kVersion != 'DEV';
const kFlutterVersion = '3.38.3';
const kFlutterRepo = 'https://storage.googleapis.com/flutter_infra_release/releases/stable';
const kChocoInstall =
    "Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))";

final cli = http.Client();
final exe = File(kIsRelease ? 'build_script.exe' : basename(Platform.script.path));
final outdated = <String>[];
String out = '';

void main(List<String> args) async {
  final plats = <String>[];
  final platArg = args.where((a) => a.startsWith('--platforms')).firstOrNull;
  if (platArg != null) {
    platArg.split('=').last.split(',').forEach((p) {
      final plat = p.trim().toLowerCase();
      if (plat.isNotEmpty) plats.add(plat);
    });
  }

  try {
    final isAdmin = bool.parse(
      (Process.runSync(
                  'powershell',
                  [
                    '([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)',
                  ],
                  runInShell: true)
              .stdout as String)
          .toLowerCase()
          .trim(),
    );

    if (kIsRelease && !isAdmin) {
      throw 'This program requires elevation';
    }

    if (args.length < 2) args = ['', ''];
    var [appName, appVersion] = args;

    if (kIsRelease) {
      final pubspec = File('pubspec.yaml');
      if (await pubspec.exists()) {
        final yaml = loadYaml(await pubspec.readAsString());
        if (yaml['dependencies']?['flutter']?['sdk'] != 'flutter') {
          throw 'Project is not a flutter project';
        }

        appName = yaml['app_name'] ?? appName;
        appVersion = yaml['version'] ?? appVersion;
      } else {
        throw 'Pubspec not found, this program must be placed at project root';
      }
    }

    if (kIsRelease) {
      info('App name: ');
      if (appName.isEmpty) {
        appName = (stdin.readLineSync() ?? '').replaceAll(' ', '').trim();
      } else {
        info(appName, true);
      }

      info('App version: ');
      if (appVersion.isEmpty) {
        appVersion = (stdin.readLineSync() ?? '').replaceAll(' ', '').trim();
      } else {
        info(appVersion, true);
      }
    } else {
      appName = 'debug';
      appVersion = '0';
    }

    if (appName.isEmpty || appVersion.isEmpty) {
      info(
        '''
        Usage:
        - ${Platform.script.pathSegments.last} ${Green('[App name]')} ${Green('[App version]')}
        '''
            .replaceAll(RegExp(r'^\s+', multiLine: true), ''),
      );

      throw 'An app name and version are required';
    }

    if (kIsRelease) {
      final pubspec = File('pubspec.yaml');
      final lines = await pubspec.readAsLines();
      final idx = lines.indexWhere((l) => l.startsWith('description:'));

      if (!lines.any((l) => l.startsWith('app_name:'))) {
        lines.insert(idx + 1, 'app_name: $appName');
        info('App name parameter added to pubspec, future executions will read from there instead');
      }

      if (!lines.any((l) => l.startsWith('version:'))) {
        lines.insert(idx + 1, 'version: $appVersion');
        info('App version parameter added to pubspec, future executions will read from there instead');
      }

      await pubspec.writeAsString(lines.join('\n'));
    }

    info('BuildScript Version $kVersion');

    info('---------------------------------------------------');

    info('Checking for updates...');
    final res = await cli.send(http.Request('HEAD', Uri.parse('$kRepository/releases/latest'))..followRedirects = false);
    if (res.headers.containsKey('location')) {
      final latest = res.headers['location']!.split('/').last;

      if (kVersion != latest) {
        info('available', true);
        if (kIsRelease) {
          await exe.rename('${exe.path}.old');
        }

        info('Downloading new version');
        final resExe = await http.get(Uri.parse('$kRepository/releases/download/$latest/build_script.exe'));
        info(Green('Download complete'));

        final hash = md5.convert(resExe.bodyBytes).toString().toUpperCase();
        {
          final resHash = await http.get(Uri.parse('$kRepository/releases/download/$latest/checksum.md5'));
          if (hash == resHash.body.trim()) {
            if (kIsRelease) {
              info('Restarting program...');
              await exe.writeAsBytes(resExe.bodyBytes, flush: true);
              await Process.start('powershell', ['del "${exe.path}.old"; start "${exe.path}" ${args.join(' ')}'], runInShell: true);
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
      'Chocolatey': () async => await exec('choco', args: ['--version'], packageId: 'chocolatey', installScript: kChocoInstall, writeOutput: false),
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
          '/*.iss',
        ]);

        await gitignore.writeAsString(lines.join('\n'));
        info('Added paths to .gitignore');
      }
    }

    final output = Directory('./output');
    if (!await output.exists()) {
      await output.create();
    } else {
      await for (final f in output.list()) {
        await f.delete();
      }
    }

    final pubspec = File('pubspec.yaml');
    final yaml = loadYaml(await pubspec.readAsString());

    if ((plats.isEmpty || plats.contains('windows')) && await Directory('./windows').exists()) {
      info('--------------------- WINDOWS ---------------------');
      /* Remake Installer */
      {
        final installer = File('Installer.iss');
        final nameParts = appName.split(RegExp(r'(?<=.)(?=[A-Z][a-z])'));
        final uuid = Uuid();

        final props = {
          'TITLE': nameParts.join(' '),
          'VERSION': appVersion,
          'EXENAME': yaml['name'],
          'GUID': uuid.v5(Namespace.url.value, 'bels.com.br/${yaml['name']}'),
          'NAME': appName,
        };

        await installer.writeAsString(kInstaller.replaceAllMapped(RegExp(r'{{(\w+)}}'), (match) => props[match[1]] ?? ''));
      }

      /* Remake CodeDependencies */
      {
        final res = await http.get(Uri.parse('https://raw.githubusercontent.com/DomGries/InnoDependencyInstaller/refs/heads/master/CodeDependencies.iss'));
        if (res.statusCode ~/ 100 == 2) {
          final codeDeps = File('CodeDependencies.iss');
          await codeDeps.writeAsBytes(res.bodyBytes);
        }
      }

      final icon = File('asset/installer.ico');
      if (!await icon.exists()) {
        warn('Installer icon not found, using fallback icon (path: ./asset/installer.ico)');
        final res = await http.get(Uri.parse('$kBlobs/fallback/installer.ico'));
        await icon.writeAsBytes(res.bodyBytes);
      }

      await exec('flutter', args: ['build', 'windows']) &&
          await exec('iscc', args: ['Installer.iss'], path: r'C:\Program Files (x86)\Inno Setup 6\') &&
          await exec(
            'rar',
            args: ['a', '-df', '-ep1', join(output.path, 'Windows_${appName}_$appVersion.rar'), join(output.path, '${appName}_setup.exe')],
            path: r'C:\Program Files\WinRAR\',
          );
    }

    if ((plats.isEmpty || plats.contains('linux')) && await Directory('./linux').exists()) {
      info('---------------------  LINUX  ---------------------');
      await exec('wsl', args: ['--update']);
      final hasDebian = (Process.runSync('wsl', ['--list'], runInShell: true).stdout as String) //
          .replaceAll('\u0000', '')
          .split(Platform.lineTerminator)
          .any((d) => d.startsWith('Debian'));

      if (!hasDebian) {
        info('Installing WSL (Debian)...');
        await exec('wsl', args: ['--install', 'Debian']);
      }

      const sudo = ['-u', 'root'];
      final config = await exec('wsl', args: [...sudo, 'apt', 'update', '-y']) &&
          await exec('wsl', args: [...sudo, 'apt', 'install', '-y', 'crudini']) &&
          await exec('wsl', args: [...sudo, 'crudini', '--ini-options=nospace', '--set', '/etc/wsl.conf', 'automount', 'options', '"metadata"']) &&
          await exec('wsl', args: [...sudo, 'crudini', '--ini-options=nospace', '--set', '/etc/wsl.conf', 'interop', 'appendWindowsPath', 'false']) &&
          await exec('wsl', args: ['--shutdown']);

      if (!config) {
        throw 'Failed to configure WSL';
      }

      const deps = [
        'curl',
        'git',
        'unzip',
        'xz-utils',
        'zip',
        'libglu1-mesa',
        'clang',
        'cmake',
        'ninja-build',
        'pkg-config',
        'libgtk-3-dev',
        'liblzma-dev',
        'libstdc++-12-dev',
      ];

      final devDeps = <String>[];
      {
        final depFile = File('.dev-dependencies');
        if (await depFile.exists()) {
          devDeps.addAll(await depFile.readAsLines());
        }
        info('Found build dependencies: ${devDeps.join(', ')}');
      }

      final useDeps = <String>[];
      {
        final depFile = File('.dependencies');
        if (await depFile.exists()) {
          useDeps.addAll(await depFile.readAsLines());
        }
        info('Found required dependencies: ${useDeps.join(', ')}');
      }

      info('Verifying Flutter installation...');

      while (true) {
        await exec('wsl', args: [...sudo, 'apt', 'install', '-y', ...deps, ...devDeps]);

        if (await exec('wsl', args: ['flutter', '--version'], writeOutput: false)) {
          info('OK', true);
          break;
        }

        info('Downloading Flutter...');
        if (!await exec('wsl', args: ['ls', '~/flutter.tar.xz'], writeOutput: false)) {
          final downloaded = await exec('wsl', args: ['curl', '$kFlutterRepo/linux/flutter_linux_$kFlutterVersion-stable.tar.xz', '-o', '~/flutter.tar.xz']);
          if (!downloaded) {
            throw 'Failed to download package';
          }
        }

        info('Extracting files...');
        await exec('wsl', args: ['rm', '-r', '~/flutter']);

        final homeDir = (Process.runSync('wsl', ['echo', '~'], runInShell: true).stdout as String).trim();
        await exec('wsl', args: ['tar', '-xvf', '~/flutter.tar.xz', '-C', '~/']) &&
            await exec('wsl', args: [...sudo, 'ln', '-s', '$homeDir/flutter/bin/flutter', '/usr/bin']) &&
            await exec('wsl', args: [...sudo, 'ln', '-s', '$homeDir/flutter/bin/dart', '/usr/bin']);
      }

      final name = yaml['name'] as String;
      final packName = name.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z0-9-+]'), '-');
      final root = 'build/build_script';
      final built = await exec('wsl', args: ['flutter', 'clean']) &&
          await exec('wsl', args: ['flutter', 'build', 'linux']) &&
          await exec('wsl', args: ['mkdir', '-p', '$root/$name/opt/bels/$name']) &&
          await exec('wsl', args: ['mkdir', '-p', '$root/$name/DEBIAN']) &&
          await exec('wsl', args: [...sudo, 'chmod', '755', '$root/$name/DEBIAN']) &&
          await exec('wsl', args: ['cp', '-r', 'build/linux/x64/release/bundle/*', '$root/$name/opt/bels/$name/']) &&
          await exec('wsl', args: [...sudo, 'chmod', '777', '$root/$name/opt/bels/$name/']);

      if (!built) {
        throw 'Failed to buid application';
      }

      final props = {
        'PACKAGE': packName,
        'EXENAME': name,
        'VERSION': appVersion,
      };

      final control = File('./$root/$name/DEBIAN/control');
      if (!await control.exists()) {
        await control.create();
      }

      await control.writeAsString(kControl.replaceAllMapped(RegExp(r'{{(\w+)}}'), (match) => props[match[1]] ?? ''));
      if (useDeps.isNotEmpty) {
        await control.writeAsString('Depends: ${useDeps.join(',')}\n', mode: FileMode.append);
      }
      await exec('wsl', args: [...sudo, 'chmod', '555', control.path]);

      info('Packing application...');
      await exec('wsl', args: ['dpkg-deb', '--build', '$root/$name']) &&
          await exec('wsl', args: ['mv', '$root/$name.deb', output.path]) &&
          await exec(
            'rar',
            args: ['a', '-df', '-ep1', join(output.path, 'Linux_${appName}_$appVersion.rar'), join(output.path, '$name.deb')],
            path: r'C:\Program Files\WinRAR\',
          );
    }

    if ((plats.isEmpty || plats.contains('android')) && await Directory('./android').exists()) {
      info('--------------------- ANDROID ---------------------');

      final built = await exec('flutter', args: ['build', 'apk']);
      if (built) {
        File apk = File('build/app/outputs/flutter-apk/app-release.apk');
        if (await apk.exists()) {
          apk = await apk.rename('${apk.parent.path}/$appName.apk');
          await exec('rar', args: ['a', '-ep1', join(output.path, 'Android_${appName}_$appVersion.rar'), apk.path], path: r'C:\Program Files\WinRAR\');
        }
      }
    }

    if ((plats.isEmpty || plats.contains('web')) && await Directory('./web').exists()) {
      info('---------------------   WEB   ---------------------');

      final built = await exec('flutter', args: ['build', 'web']);
      if (built) {
        final dir = Directory('build/web');
        await exec('rar',
            args: ['a', '-r', '-ep1', join(output.path, 'Web_${appName}_$appVersion.rar'), join(dir.path, '*')], path: r'C:\Program Files\WinRAR\');
      }
    }
  } catch (e) {
    error(e);
    info('\nPress any key to exit...');
    stdin.readLineSync();
    exit(1);
  } finally {
    info('\nPress any key to exit...');
    stdin.readLineSync();
    exit(0);
  }
}

Future<bool> exec(String program, {String path = '', List<String> args = const [], String? packageId, String? installScript, bool writeOutput = true}) async {
  try {
    if (packageId != null) {
      if (packageId == 'chocolatey') {
        final String out = Process.runSync('choco', ['outdated'], runInShell: true).stdout;
        final rex = RegExp(r'([\w-.]+?)\|[\d.]+?\|[\d.]+?\|false', multiLine: true);
        for (final m in rex.allMatches(out)) {
          outdated.add(m.group(1)!);
        }
      }

      if (outdated.contains(packageId)) {
        info('New version found, type "y" to update: ');
        final opt = (stdin.readLineSync() ?? '').toLowerCase();
        if (opt == 'y') {
          if (Process.runSync('choco', ['upgrade', '-y', packageId], runInShell: true).exitCode != 0) {
            throw 'Failed to update dependency "$program", aborting execution';
          }
        }
      }
    }

    if (writeOutput) {
      if (!out.endsWith('\n')) info('');

      final proc = await Process.start('$path$program', args, runInShell: true)
        ..stdout.forEach((bytes) => info(String.fromCharCodes(bytes.where((b) => b > 0)), true))
        ..stderr.forEach((bytes) => error(String.fromCharCodes(bytes.where((b) => b > 0)), true));

      return await proc.exitCode == 0;
    }

    return Process.runSync('$path$program', args, runInShell: true).exitCode == 0;
  } on ProcessException {
    if (packageId != null || installScript != null) {
      info('Process "$program" not found, installing...\n');

      if (installScript != null) {
        final prog = installScript.split(' ').first;
        final args = installScript.replaceFirst(prog, '').trim();

        if (await Process.start(prog, [args], runInShell: true, mode: ProcessStartMode.inheritStdio).then((p) => p.exitCode) != 0) {
          throw 'Failed to install dependency "$program", aborting execution';
        }
      }

      info('Installed "$program" successfully');
      return exec(program, path: path, args: args, packageId: packageId, installScript: installScript, writeOutput: writeOutput);
    }

    throw 'Process "$program" not found, please install before proceeding';
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
  final line = '${inline ? '' : '\n'}$content';
  stdout.write(line);
  out += line;
}
