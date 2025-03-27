class ConsoleColor {
  final String content;
  final int code;

  const ConsoleColor(this.code, this.content);

  @override
  String toString() => '\x1B[${code}m$content\x1B[0m';
}

class Black extends ConsoleColor {
  Black(String content) : super(30, content);
}
class Red extends ConsoleColor {
  Red(String content) : super(31, content);
}
class Green extends ConsoleColor {
  Green(String content) : super(32, content);
}
class Yellow extends ConsoleColor {
  Yellow(String content) : super(33, content);
}
class Blue extends ConsoleColor {
  Blue(String content) : super(34, content);
}
class Magenta extends ConsoleColor {
  Magenta(String content) : super(35, content);
}
class Cyan extends ConsoleColor {
  Cyan(String content) : super(36, content);
}
class White extends ConsoleColor {
  White(String content) : super(37, content);
}