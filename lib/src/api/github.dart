// GitHub on every release: a git tag, a GitHub Deployment with status, a
// commit status, and for chosen environments a GitHub Release with notes.
//
// It uses the `gh` CLI (the user's own auth) or `GITHUB_TOKEN`. A GitHub
// failure never fails a deploy: it becomes a warning.

import 'dart:convert';
import 'dart:io';

import '../config/config.dart';
import '../util/log.dart';

/// Runs `gh` and returns stdout, or throws with its stderr.
Future<String> _gh(List<String> args, {String? input, String? cwd}) async {
  final proc = await Process.start('gh', args, workingDirectory: cwd);
  if (input != null) proc.stdin.write(input);
  await proc.stdin.close();
  final out = await proc.stdout.transform(utf8.decoder).join();
  final err = await proc.stderr.transform(utf8.decoder).join();
  if (await proc.exitCode != 0) {
    throw Exception('gh ${args.take(3).join(' ')}: ${err.trim()}');
  }
  return out;
}

Future<String> _git(String root, List<String> args) async {
  final r = await Process.run('git', args, workingDirectory: root);
  if (r.exitCode != 0) {
    throw Exception('git ${args.join(' ')}: ${(r.stderr as String).trim()}');
  }
  return (r.stdout as String).trim();
}

class GitHub {
  GitHub(this.config, this.log);
  final PodshipConfig config;
  final Log log;

  GitHubConfig? get gh => config.github;

  Future<void> _try(String what, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      log.warn('GitHub: $what failed: $e');
    }
  }

  /// The public URL of [env], for deployments.
  String? envUrl(EnvConfig env) =>
      env.domains.isEmpty ? null : 'https://${env.domains.first.host}';

  /// Starts a GitHub Deployment of [sha] to [env]. Returns its id.
  Future<int?> startDeployment(
    EnvConfig env,
    String sha,
    String release,
  ) async {
    final g = gh;
    if (g == null || !g.deployments) return null;
    int? id;
    await _try('deployment', () async {
      final out = await _gh(
        ['api', 'repos/${g.repo}/deployments', '--input', '-'],
        input: jsonEncode({
          'ref': sha,
          'environment': env.name,
          'description': 'podship $release',
          'auto_merge': false,
          'required_contexts': <String>[],
          'production_environment': env.isProduction,
          'payload': {'release': release, 'host': env.host},
        }),
      );
      id = (jsonDecode(out) as Map)['id'] as int?;
      if (id != null) await _status(g, id!, 'in_progress', env);
    });
    return id;
  }

  Future<void> _status(
    GitHubConfig g,
    int id,
    String state,
    EnvConfig env, {
    String? description,
  }) => _gh(
    ['api', 'repos/${g.repo}/deployments/$id/statuses', '--input', '-'],
    input: jsonEncode({
      'state': state,
      'environment': env.name,
      'environment_url': ?envUrl(env),
      'description': ?description,
      'auto_inactive': true,
    }),
  );

  /// Ends a deployment: success or failure.
  Future<void> finishDeployment(
    EnvConfig env,
    int? id, {
    required bool ok,
    String? description,
  }) async {
    final g = gh;
    if (g == null || id == null) return;
    await _try(
      'deployment status',
      () => _status(
        g,
        id,
        ok ? 'success' : 'failure',
        env,
        description: description,
      ),
    );
  }

  /// Marks the newest successful deployment of [env] for [sha] inactive
  /// (after a rollback away from it).
  Future<void> markInactive(EnvConfig env, String sha) async {
    final g = gh;
    if (g == null || !g.deployments) return;
    await _try('mark inactive', () async {
      final out = await _gh([
        'api',
        'repos/${g.repo}/deployments?environment=${env.name}&sha=$sha&per_page=1',
      ]);
      final list = jsonDecode(out) as List;
      if (list.isEmpty) return;
      await _status(
        g,
        (list.first as Map)['id'] as int,
        'inactive',
        env,
        description: 'rolled back',
      );
    });
  }

  /// Sets the `podship/deploy/<env>` commit status.
  Future<void> commitStatus(
    EnvConfig env,
    String sha, {
    required bool ok,
    required String description,
  }) async {
    final g = gh;
    if (g == null || !g.statuses) return;
    await _try(
      'commit status',
      () => _gh(
        ['api', 'repos/${g.repo}/statuses/$sha', '--input', '-'],
        input: jsonEncode({
          'state': ok ? 'success' : 'failure',
          'context': 'podship/deploy/${env.name}',
          'description': description.length > 140
              ? description.substring(0, 140)
              : description,
          'target_url': ?envUrl(env),
        }),
      ),
    );
  }

  /// Creates and pushes the tag `podship/<env>/<release>` on [sha].
  Future<void> tag(EnvConfig env, String sha, String release) async {
    final g = gh;
    if (g == null || !g.tags) return;
    final name = 'podship/${env.name}/$release';
    await _try('tag $name', () async {
      await _gh([
        'api',
        'repos/${g.repo}/git/refs',
        '--input',
        '-',
      ], input: jsonEncode({'ref': 'refs/tags/$name', 'sha': sha}));
      // Also locally, so `git describe` and `git tag --contains` see it.
      await Process.run('git', [
        'tag',
        '-f',
        name,
        sha,
      ], workingDirectory: config.root);
    });
  }

  /// The release notes for [sha]: commits since [previousSha], merged pull
  /// requests, `Implements:` trailers as features, and the test summary.
  Future<String> releaseNotes(
    String sha,
    String? previousSha, {
    Map<String, Object?>? tests,
    String? release,
  }) async {
    final range = previousSha == null || previousSha.length < 7
        ? sha
        : '$previousSha..$sha';
    final log = await _git(config.root, [
      'log',
      '--format=%H%x09%s%x09%(trailers:key=Implements,valueonly,separator=%x2C)',
      range,
    ]);
    final commits = <String>[], prs = <String>[], features = <String>{};
    for (final line in const LineSplitter().convert(log)) {
      final parts = line.split('\t');
      if (parts.length < 2) continue;
      final subject = parts[1];
      final pr =
          RegExp(r'Merge pull request #(\d+)').firstMatch(subject) ??
          RegExp(r'\(#(\d+)\)$').firstMatch(subject);
      if (pr != null) prs.add('#${pr[1]} $subject');
      commits.add('- ${parts[0].substring(0, 7)} $subject');
      if (parts.length > 2) {
        for (final f in parts[2].split(',')) {
          if (f.trim().isNotEmpty) features.add(f.trim());
        }
      }
    }
    final b = StringBuffer();
    if (release != null) {
      b.writeln(
        'podship release `$release`, commit `${sha.substring(0, 7)}`.\n',
      );
    }
    if (features.isNotEmpty) {
      b.writeln('## Features\n');
      for (final f in features.toList()..sort()) {
        b.writeln('- $f');
      }
      b.writeln();
    }
    if (prs.isNotEmpty) {
      b.writeln('## Pull requests\n');
      for (final p in prs) {
        b.writeln('- $p');
      }
      b.writeln();
    }
    b.writeln(
      '## Commits${previousSha == null ? '' : ' since ${previousSha.substring(0, 7)}'}\n',
    );
    b.writeln(commits.isEmpty ? '- (none)' : commits.take(200).join('\n'));
    if (tests != null) {
      b.writeln('\n## Tests\n');
      if (tests['passed_in'] != null) {
        b.writeln('Passed in the ${tests['passed_in']} deploy of this commit.');
      } else if (tests['skipped'] == true) {
        b.writeln('Skipped: ${tests['reason']}');
      } else {
        for (final s in (tests['suites'] as List? ?? const [])) {
          final m = s as Map;
          b.writeln(
            '- ${m['suite']}: ${m['passed']} passed, ${m['skipped']} skipped, ${m['failed']} failed',
          );
        }
      }
    }
    return b.toString();
  }

  /// The next release tag for today.
  Future<String> nextReleaseTag() async {
    final g = gh!;
    final now = DateTime.now().toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${now.year}.${two(now.month)}.${two(now.day)}';
    final prefix = g.releaseTag.replaceAll('{date}', date).split('{n}').first;
    final out = await _gh([
      'api',
      'repos/${g.repo}/releases?per_page=100',
      '--jq',
      '.[].tag_name',
    ]);
    var n = 1;
    for (final t in const LineSplitter().convert(out)) {
      if (t.startsWith(prefix)) {
        final k = int.tryParse(t.substring(prefix.length)) ?? 0;
        if (k >= n) n = k + 1;
      }
    }
    return g.releaseTag.replaceAll('{date}', date).replaceAll('{n}', '$n');
  }

  /// Creates a GitHub Release for a deploy of [sha] to [env].
  Future<String?> release(
    EnvConfig env,
    String sha,
    String podshipRelease,
    String? previousSha, {
    Map<String, Object?>? tests,
  }) async {
    final g = gh;
    if (g == null || !g.releases.contains(env.name)) return null;
    String? url;
    await _try('release', () async {
      final tag = await nextReleaseTag();
      final notes = await releaseNotes(
        sha,
        previousSha,
        tests: tests,
        release: podshipRelease,
      );
      final out = await _gh(
        ['api', 'repos/${g.repo}/releases', '--input', '-'],
        input: jsonEncode({
          'tag_name': tag,
          'target_commitish': sha,
          'name': '$tag (${env.name})',
          'body': notes,
        }),
      );
      url = (jsonDecode(out) as Map)['html_url'] as String?;
      log.info('GitHub release $tag: $url');
    });
    return url;
  }

  /// Adds a note to the GitHub Release of [sha] after a rollback.
  Future<void> noteRollback(
    EnvConfig env,
    String fromSha,
    String toRelease,
  ) async {
    final g = gh;
    if (g == null || !g.releases.contains(env.name)) return;
    await _try('release note', () async {
      final out = await _gh(['api', 'repos/${g.repo}/releases?per_page=30']);
      for (final r in jsonDecode(out) as List) {
        final m = r as Map;
        if ('${m['target_commitish']}' == fromSha) {
          await _gh(
            [
              'api',
              '-X',
              'PATCH',
              'repos/${g.repo}/releases/${m['id']}',
              '--input',
              '-',
            ],
            input: jsonEncode({
              'body':
                  '${m['body']}\n\n> Rolled back on ${DateTime.now().toUtc().toIso8601String()} to podship release `$toRelease`.',
            }),
          );
          return;
        }
      }
    });
  }
}
