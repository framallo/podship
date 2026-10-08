// `docker save` archives, and sending only the layers a server lacks.
//
// An archive holds `manifest.json`, `index.json`, `oci-layout` and
// `blobs/sha256/<digest>`. Each image in `manifest.json` names its config
// blob and its layer blobs in order; the config's `rootfs.diff_ids` gives
// the uncompressed digest (DiffID) of each layer, in the same order. A
// server lists the DiffIDs of its images with `docker image inspect`. A
// layer whose DiffID the server has is left out of the archive: with the
// containerd image store, `docker load` takes an archive without the blobs
// the store already holds. When a trimmed load fails, podship sends the
// whole archive.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// One image in a `docker save` archive.
class SavedImage {
  SavedImage({
    required this.config,
    required this.tags,
    required this.layers,
    required this.diffIds,
  });

  /// The config blob path, like `blobs/sha256/…`.
  final String config;
  final List<String> tags;

  /// The layer blob paths, in order.
  final List<String> layers;

  /// The DiffID of each layer, in the same order.
  final List<String> diffIds;
}

/// Reads the images of an extracted archive in [dir].
List<SavedImage> readArchive(String dir) {
  final manifest = jsonDecode(
    File(p.join(dir, 'manifest.json')).readAsStringSync(),
  );
  if (manifest is! List) throw FormatException('manifest.json is not a list');
  return [
    for (final m in manifest.cast<Map<String, Object?>>())
      () {
        final config = m['Config'] as String;
        final cfg =
            jsonDecode(File(p.join(dir, config)).readAsStringSync())
                as Map<String, Object?>;
        final rootfs = (cfg['rootfs'] as Map?) ?? const {};
        return SavedImage(
          config: config,
          tags: [for (final t in (m['RepoTags'] as List? ?? const [])) '$t'],
          layers: [for (final l in (m['Layers'] as List? ?? const [])) '$l'],
          diffIds: [
            for (final d in (rootfs['diff_ids'] as List? ?? const [])) '$d',
          ],
        );
      }(),
  ];
}

/// The layer blobs of [images] that the server already has, by DiffID.
/// A blob is left out only when every image that uses it maps it to a
/// DiffID in [serverDiffIds].
Set<String> blobsToSkip(List<SavedImage> images, Set<String> serverDiffIds) {
  final skip = <String>{};
  final keep = <String>{};
  for (final img in images) {
    if (img.layers.length != img.diffIds.length) {
      keep.addAll(img.layers);
      continue;
    }
    for (final (i, layer) in img.layers.indexed) {
      if (serverDiffIds.contains(img.diffIds[i])) {
        skip.add(layer);
      } else {
        keep.add(layer);
      }
    }
  }
  return skip.difference(keep);
}

/// Parses the output of [serverDiffIdsScript]: one JSON list per line.
Set<String> parseDiffIds(String out) {
  final ids = <String>{};
  for (final line in out.split('\n')) {
    final l = line.trim();
    if (!l.startsWith('[')) continue;
    try {
      for (final x in jsonDecode(l) as List) {
        ids.add('$x');
      }
    } on FormatException {
      continue;
    }
  }
  return ids;
}

/// Lists the DiffIDs of every image on the server, one JSON list per image.
const serverDiffIdsScript = r'''
ids=$(docker images -q 2>/dev/null | sort -u)
[ -z "$ids" ] || docker image inspect --format '{{json .RootFS.Layers}}' $ids 2>/dev/null || true
''';

/// The files of the extracted archive [dir], relative, without [skip].
List<String> archiveFiles(String dir, Set<String> skip) {
  final out = <String>[];
  for (final e in Directory(
    dir,
  ).listSync(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final rel = p.relative(e.path, from: dir).replaceAll(r'\', '/');
    if (!skip.contains(rel)) out.add(rel);
  }
  out.sort();
  return out;
}

/// The total size of [files] in [dir].
int sizeOf(String dir, Iterable<String> files) {
  var n = 0;
  for (final f in files) {
    n += File(p.join(dir, f)).lengthSync();
  }
  return n;
}

/// `12.3 MB`.
String mb(int bytes) => '${(bytes / 1e6).toStringAsFixed(1)} MB';
