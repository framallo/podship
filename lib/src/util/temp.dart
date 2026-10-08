import 'dart:io';

/// The folder for release exports. macOS's system temp folder
/// (`/var/folders/…/T`) is long, and tools that put Unix sockets inside the
/// project (an embedded Postgres in the server's tests) pass the 104-byte
/// socket path limit there. `/tmp` keeps the paths short.
Directory exportRoot() {
  if (!Platform.isWindows) {
    final tmp = Directory('/tmp');
    if (tmp.existsSync()) return tmp;
  }
  return Directory.systemTemp;
}

/// A new, empty export folder with [prefix].
Future<Directory> createExportDir(String prefix) =>
    exportRoot().createTemp(prefix);
