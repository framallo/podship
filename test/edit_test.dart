import 'package:podship/src/edit/dotenv.dart';
import 'package:podship/src/edit/passwords.dart';
import 'package:test/test.dart';

void main() {
  group('DotEnv', () {
    const text = '# comment\nA=1\n\n# podship: plain\nPORT=8087\nKEY="a b"\n';
    test('reads names and values', () {
      final f = DotEnv(text);
      expect(f.names, ['A', 'PORT', 'KEY']);
      expect(f.get('KEY'), 'a b');
      expect(f.markedPlain('PORT'), isTrue);
      expect(f.markedPlain('A'), isFalse);
    });
    test('sets values and keeps comments and order', () {
      final f = DotEnv(text)
        ..set('A', '2')
        ..set('NEW', "it's \$x", plain: true);
      expect(f.toString(), startsWith('# comment\nA=2\n'));
      expect(f.get('NEW'), "it's \$x");
      expect(f.markedPlain('NEW'), isTrue);
    });
    test('a secret set over a plain value loses the marker', () {
      final f = DotEnv(text)..set('PORT', '1');
      expect(f.markedPlain('PORT'), isFalse);
    });
    test('unset removes the line and its marker', () {
      final f = DotEnv(text)..unset('PORT');
      expect(f.toString(), isNot(contains('podship: plain')));
      expect(f.unset('NOPE'), isFalse);
    });
    test('quoting round-trips', () {
      for (final v in ['plain', 'with space', "q'uote", 'back\\slash "dq"', r'$HOME', 'a+b/c=']) {
        final f = DotEnv('')..set('V', v);
        expect(DotEnv(f.toString()).get('V'), v, reason: f.toString());
      }
    });
    test('rejects invalid names', () {
      expect(() => DotEnv('').set('1A', 'x'), throwsArgumentError);
    });
  });

  group('PasswordsFile', () {
    test('sets keys in a section and keeps comments', () {
      final f = PasswordsFile('# secrets\nshared:\n  a: x\n')
        ..set('production', 'database', 'pw')
        ..set('shared', 'a', 'y');
      final t = f.toString();
      expect(t, startsWith('# secrets'));
      expect(f.get('production', 'database'), 'pw');
      expect(f.get('shared', 'a'), 'y');
      expect(f.keys('production'), ['database']);
    });
    test('starts from an empty file', () {
      final f = PasswordsFile('')..set('production', 'k', 'v');
      expect(PasswordsFile(f.toString()).get('production', 'k'), 'v');
    });
    test('unset', () {
      final f = PasswordsFile('production:\n  a: 1\n  b: 2\n');
      expect(f.unset('production', 'a'), isTrue);
      expect(f.keys('production'), ['b']);
      expect(f.unset('production', 'z'), isFalse);
    });
  });
}
