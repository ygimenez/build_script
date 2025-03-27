class ConsoleColor {
  final String content;
  final int code;

  const ConsoleColor(this.code, this.content);

  @override
  String toString() => '\x1B[${code}m$content\x1B[0m';
}

class Default extends ConsoleColor {
  Default(content) : super(0, content.toString());
}

class Black extends ConsoleColor {
  Black(content) : super(30, content.toString());
}

class Red extends ConsoleColor {
  Red(content) : super(31, content.toString());
}

class Green extends ConsoleColor {
  Green(content) : super(32, content.toString());
}

class Yellow extends ConsoleColor {
  Yellow(content) : super(33, content.toString());
}

class Blue extends ConsoleColor {
  Blue(content) : super(34, content.toString());
}

class Magenta extends ConsoleColor {
  Magenta(content) : super(35, content.toString());
}

class Cyan extends ConsoleColor {
  Cyan(content) : super(36, content.toString());
}

class White extends ConsoleColor {
  White(content) : super(37, content.toString());
}
