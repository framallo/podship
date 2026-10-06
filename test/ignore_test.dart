import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:podship/src/files/ignore.dart';
import 'package:test/test.dart';

void main() {
  group('globToRegex', () {
    bool m(String glob, String path) =>
        RegExp('^${globToRegex(glob)}\$').hasMatch(path);
    test('star stays in one segment', () {
      expect(m('*.dart', 'a.dart'), isTrue);
      expect(m('*.dart', 'lib/a.dart'), isFalse);
    });
    test('double star crosses segments', () {
      expect(m('web/**', 'web/a/b.js'), isTrue);
      expect(m('**/x', 'a/b/x'), isTrue);
      expect(m('**/x', 'x'), isTrue);
      expect(m('a/**/z', 'a/z'), isTrue);
      expect(m('a/**/z', 'a/b/c/z'), isTrue);
    });
    test('character classes and question marks', () {
      expect(m('f?.[ch]', 'f1.c'), isTrue);
      expect(m('f[!a].c', 'fa.c'), isFalse);
    });
  });

  group('IgnoreRule', () {
    test('a pattern without a slash matches at any depth', () {
      final r = IgnoreRule.parse('build')!;
      expect(r.matches('build', isDir: true), isTrue);
      expect(r.matches('a/b/build', isDir: true), isTrue);
    });
    test('a slash anchors the pattern to its file', () {
      final r = IgnoreRule.parse('web/app', base: 'server')!;
      expect(r.matches('server/web/app', isDir: true), isTrue);
      expect(r.matches('web/app', isDir: true), isFalse);
      expect(r.matches('other/server/web/app', isDir: true), isFalse);
    });
    test('a trailing slash matches only directories', () {
      final r = IgnoreRule.parse('logs/')!;
      expect(r.matches('logs', isDir: true), isTrue);
      expect(r.matches('logs', isDir: false), isFalse);
    });
    test('comments and blank lines are not rules', () {
      expect(IgnoreRule.parse('# x'), isNull);
      expect(IgnoreRule.parse('   '), isNull);
      expect(IgnoreRule.parse(r'\#x')!.matches('#x', isDir: false), isTrue);
    });
  });

  group('FileRules', () {
    test('the last matching rule wins', () {
      final rules = FileRules([
        IgnoreRule.parse('*.log')!,
        IgnoreRule.parse('!keep.log')!,
      ]);
      expect(rules.includes('a.log'), isFalse);
      expect(rules.includes('keep.log'), isTrue);
      expect(rules.includes('a.txt'), isTrue);
    });
    test(
      'an excluded directory excludes its files, and a later rule includes them again',
      () {
        final rules = FileRules([
          IgnoreRule.parse('web/app', base: 'server')!,
          IgnoreRule.parse('!server/web/app/**')!,
        ]);
        expect(rules.includes('server/web/app/main.dart.js'), isTrue);
        final only = FileRules([IgnoreRule.parse('web/app', base: 'server')!]);
        expect(only.includes('server/web/app/main.dart.js'), isFalse);
      },
    );
    test('secrets never ship, whatever the rules say', () {
      final rules = FileRules([IgnoreRule.parse('!**')!]);
      expect(rules.includes('.env'), isFalse);
      expect(rules.includes('server/config/passwords.yaml'), isFalse);
      expect(rules.includes('.git/config'), isFalse);
      expect(rules.includes('keys/deploy.pem'), isFalse);
      expect(rules.includes('.env.ejemplo'), isTrue);
      expect(rules.includes('.env.example'), isTrue);
    });
  });

  group('selectFiles', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('podship-ignore-'));
    tearDown(() => root.deleteSync(recursive: true));

    void file(String rel, [String text = 'x']) {
      final f = File(p.join(root.path, rel));
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(text);
    }

    test(
      'applies nested .gitignore, .podshipignore and extra rules in order',
      () {
        file('.gitignore', 'build/\n*.log\n');
        file('server/.gitignore', 'web/app\nconfig/passwords.yaml\n');
        file('server/.podshipignore', 'test/\n');
        file('server/bin/main.dart');
        file('server/config/production.yaml');
        file('server/config/passwords.yaml');
        file('server/web/app/index.html');
        file('server/test/a_test.dart');
        file('server/build/out');
        file('debug.log');
        file('docker-compose.yml');
        final got = selectFiles(
          root.path,
          extraRules: ['!server/web/app/**', 'docker-compose.yml'],
        );
        expect(
          got,
          containsAll([
            'server/bin/main.dart',
            'server/config/production.yaml',
            'server/web/app/index.html',
          ]),
        );
        expect(got, isNot(contains('server/config/passwords.yaml')));
        expect(got, isNot(contains('server/test/a_test.dart')));
        expect(got, isNot(contains('server/build/out')));
        expect(got, isNot(contains('debug.log')));
        expect(got, isNot(contains('docker-compose.yml')));
      },
    );
  });
}
