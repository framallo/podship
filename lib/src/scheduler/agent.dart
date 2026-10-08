// The scheduler agent of a machine: its launchd plist or systemd units, the
// scripts that install, query and remove it, and the import of the per
// environment agents podship used to install (`dev.podship.backup.*`,
// `dev.podship.pull.*`, `podship-backup-*.timer`).

import 'dart:convert';

import 'package:path/path.dart' as p;

import '../remote/ssh.dart';
import '../ops/scripts.dart';
import '../server/registry.dart';

/// The launchd label and the systemd unit name of the agent.
const schedulerLabel = 'dev.podship.scheduler';
const schedulerUnit = 'podship-scheduler';

/// Where the agent's podship binary lives on a machine.
String schedulerBin(String home) => p.posix.join(home, 'bin', 'podship');

/// Where a machine's launch agents live (macOS).
const launchAgentsDir = r'$HOME/Library/LaunchAgents';

/// The PATH the agent runs with.
String agentPath(String? remotePath) => [
  ?remotePath,
  '/opt/homebrew/bin',
  '/usr/local/bin',
  '/usr/bin',
  '/bin',
  '/usr/sbin',
  '/sbin',
].join(':');

/// The launchd agent: one nightly run at [settings.at], plus a run at load
/// (login, reboot) that catches up a missed night.
String schedulerPlist({
  required String home,
  required SchedulerSettings settings,
  required String path,
}) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- Written by podship: the scheduler of this machine. Jobs: $home/registry.yaml -->
<plist version="1.0">
<dict>
  <key>Label</key><string>$schedulerLabel</string>
  <key>ProgramArguments</key>
  <array>
    <string>${schedulerBin(home)}</string>
    <string>scheduler</string>
    <string>tick</string>
    <string>--home</string>
    <string>$home</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>$path</string></dict>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>${settings.hour}</integer><key>Minute</key><integer>${settings.minute}</integer></dict>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$home/log/scheduler-agent.log</string>
  <key>StandardErrorPath</key><string>$home/log/scheduler-agent.log</string>
</dict>
</plist>
''';

/// The systemd units: a persistent nightly timer and a oneshot service.
({String service, String timer}) schedulerSystemd({
  required String home,
  required SchedulerSettings settings,
  required String path,
}) => (
  service:
      '''
# Written by podship: the scheduler of this machine. Jobs: $home/registry.yaml
# Run now: systemctl start $schedulerUnit.service
# Log: $home/log/scheduler.log
[Unit]
Description=podship scheduler
Wants=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
Environment=HOME=/root
Environment=PATH=$path
ExecStart=${schedulerBin(home)} scheduler tick --home $home
Nice=10
IOSchedulingClass=idle
TimeoutStartSec=3h
''',
  timer:
      '''
# Written by podship. Persistent: a missed night runs at boot.
[Unit]
Description=podship scheduler, nightly at ${settings.at}

[Timer]
OnCalendar=*-*-* ${settings.at}:00
Persistent=true
RandomizedDelaySec=1min

[Install]
WantedBy=timers.target
''',
);

/// Installs (or updates) the agent on a Mac. The plist is registered again
/// only when it changed or is not loaded: macOS shows a "can run in the
/// background" notice at every registration.
String installLaunchdScript({
  required String home,
  required SchedulerSettings settings,
  required String path,
}) {
  final plist = schedulerPlist(home: home, settings: settings, path: path);
  return '''
mkdir -p ${shq('$home/log')} ${shq('$home/scheduler')}
${schedulerBin(home)} scheduler tick --home ${shq(home)} --seed
${writeFile('$launchAgentsDir/$schedulerLabel.plist.new', plist).replaceAll("'\$HOME/Library", '"\$HOME"\'/Library')}
dst="\$HOME/Library/LaunchAgents/$schedulerLabel.plist"
if [ -f "\$dst" ] && cmp -s "\$dst.new" "\$dst" && launchctl print gui/\$(id -u)/$schedulerLabel >/dev/null 2>&1; then
  rm -f "\$dst.new"; echo "$schedulerLabel: unchanged, still loaded"
else
  mv -f "\$dst.new" "\$dst"
  launchctl bootout gui/\$(id -u)/$schedulerLabel 2>/dev/null || true
  launchctl bootstrap gui/\$(id -u) "\$dst"
  echo "$schedulerLabel: registered (nightly at ${settings.at}, and at load)"
fi
launchctl print gui/\$(id -u)/$schedulerLabel | grep -E "state =|path =" | head -2
''';
}

/// Installs (or updates) the agent on a Linux server.
String installSystemdScript({
  required String home,
  required SchedulerSettings settings,
  required String path,
}) {
  final u = schedulerSystemd(home: home, settings: settings, path: path);
  return '''
mkdir -p ${shq('$home/log')} ${shq('$home/scheduler')}
${schedulerBin(home)} scheduler tick --home ${shq(home)} --seed
changed=0
${writeFile('/etc/systemd/system/$schedulerUnit.service.new', u.service)}
${writeFile('/etc/systemd/system/$schedulerUnit.timer.new', u.timer)}
for f in $schedulerUnit.service $schedulerUnit.timer; do
  if ! cmp -s /etc/systemd/system/\$f.new /etc/systemd/system/\$f; then mv -f /etc/systemd/system/\$f.new /etc/systemd/system/\$f; changed=1; else rm -f /etc/systemd/system/\$f.new; fi
done
if [ "\$changed" = 1 ] || ! systemctl is-enabled $schedulerUnit.timer >/dev/null 2>&1; then
  systemctl daemon-reload
  systemctl enable --now $schedulerUnit.timer
  echo "$schedulerUnit.timer: enabled (nightly at ${settings.at})"
else
  echo "$schedulerUnit.timer: unchanged, still enabled"
fi
systemctl list-timers $schedulerUnit.timer --no-pager
''';
}

/// Removes the agent. The registry and its jobs stay.
String uninstallScript({required bool macos}) => macos
    ? '''
launchctl bootout gui/\$(id -u)/$schedulerLabel 2>/dev/null || true
rm -f "\$HOME/Library/LaunchAgents/$schedulerLabel.plist"
echo "$schedulerLabel removed"
'''
    : '''
systemctl disable --now $schedulerUnit.timer 2>/dev/null || true
rm -f /etc/systemd/system/$schedulerUnit.timer /etc/systemd/system/$schedulerUnit.service
systemctl daemon-reload
echo "$schedulerUnit removed"
''';

/// Prints the agent, the state and the log of a machine. Parsed by
/// [parseStatus].
String statusScript(String home) =>
    '''
echo "OS \$(uname -s)"
if [ "\$(uname -s)" = Darwin ]; then
  if launchctl print gui/\$(id -u)/$schedulerLabel >/dev/null 2>&1; then echo "AGENT loaded"; else echo "AGENT missing"; fi
  [ -f "\$HOME/Library/LaunchAgents/$schedulerLabel.plist" ] && grep -A1 '<key>Hour</key>' "\$HOME/Library/LaunchAgents/$schedulerLabel.plist" | tr -d '\\n' | sed 's/.*Hour<\\/key><integer>\\([0-9]*\\)<\\/integer><key>Minute<\\/key><integer>\\([0-9]*\\)<\\/integer>.*/AGENT-AT \\1:\\2/'; echo
else
  if systemctl is-enabled $schedulerUnit.timer >/dev/null 2>&1; then echo "AGENT loaded"; else echo "AGENT missing"; fi
  grep -h OnCalendar /etc/systemd/system/$schedulerUnit.timer 2>/dev/null | sed 's/.*\\([0-9][0-9]:[0-9][0-9]\\):00.*/AGENT-AT \\1/'
fi
[ -x ${shq(schedulerBin(home))} ] && echo "BIN \$(${shq(schedulerBin(home))} --version 2>/dev/null)"
echo "STATE-BEGIN"
cat ${shq('$home/scheduler/state.json')} 2>/dev/null || true
echo "STATE-END"
echo "REGISTRY-BEGIN"
cat ${shq('$home/registry.yaml')} 2>/dev/null || true
echo "REGISTRY-END"
echo "LOG-BEGIN"
tail -n 20 ${shq('$home/log/scheduler.log')} 2>/dev/null || true
echo "LOG-END"
''';

/// The scheduler of one machine, as `scheduler status` shows it.
class SchedulerStatus {
  SchedulerStatus({
    required this.host,
    required this.home,
    required this.os,
    required this.agentLoaded,
    required this.agentAt,
    required this.binVersion,
    required this.registry,
    required this.state,
    required this.logTail,
  });

  final String host;
  final String home;
  final String os;
  final bool agentLoaded;

  /// The time the installed agent fires at, when it is installed.
  final String? agentAt;
  final String? binVersion;
  final Registry registry;
  final Map<String, Object?> state;
  final List<String> logTail;

  /// Jobs with their state, in run order.
  List<Map<String, Object?>> get jobs {
    final js = (state['jobs'] as Map?) ?? const {};
    return [
      for (final j in registry.orderedJobs)
        {
          'id': j.id,
          ...j.toMap(),
          ...((js[j.id] as Map?)?.cast<String, Object?>() ?? const {}),
        },
    ];
  }

  Map<String, Object?> toJson() => {
    'host': host,
    'home': home,
    'os': os,
    'agent': agentLoaded ? 'loaded' : 'missing',
    'agent_at': ?agentAt,
    'at': registry.scheduler.at,
    'podship': ?binVersion,
    'last_tick': ?state['last_tick'],
    'jobs': jobs,
    'log': logTail,
  };
}

SchedulerStatus parseStatus(
  String out, {
  required String host,
  required String home,
}) {
  var os = '';
  var loaded = false;
  String? at, bin;
  final state = StringBuffer(), reg = StringBuffer();
  final logLines = <String>[];
  String? section;
  for (final line in const LineSplitter().convert(out)) {
    if (section != null) {
      if (line == '$section-END') {
        section = null;
      } else {
        switch (section) {
          case 'STATE':
            state.writeln(line);
          case 'REGISTRY':
            reg.writeln(line);
          default:
            logLines.add(line);
        }
      }
      continue;
    }
    if (line.endsWith('-BEGIN')) {
      section = line.substring(0, line.length - 6);
    } else if (line.startsWith('OS ')) {
      os = line.substring(3).trim();
    } else if (line == 'AGENT loaded') {
      loaded = true;
    } else if (line.startsWith('AGENT-AT ')) {
      final t = line.substring(9).trim().split(':');
      if (t.length == 2) at = '${t[0].padLeft(2, '0')}:${t[1].padLeft(2, '0')}';
    } else if (line.startsWith('BIN ')) {
      bin = line.substring(4).trim();
    }
  }
  Map<String, Object?> st = const {};
  try {
    final j = jsonDecode(state.toString());
    if (j is Map) st = j.cast<String, Object?>();
  } catch (_) {}
  return SchedulerStatus(
    host: host,
    home: home,
    os: os,
    agentLoaded: loaded,
    agentAt: at,
    binVersion: bin,
    registry: Registry.parse(reg.toString()),
    state: st,
    logTail: logLines,
  );
}

// ------------------------------------------------------------- migration

/// Prints the per-environment agents podship installed before the
/// scheduler: every `dev.podship.*` launch agent as JSON (macOS), or every
/// systemd timer whose service podship wrote (Linux). Parsed by
/// [parseLegacyUnits].
const legacyScanScript =
    '''
if [ "\$(uname -s)" = Darwin ]; then
  for f in "\$HOME"/Library/LaunchAgents/dev.podship.*.plist; do
    [ -f "\$f" ] || continue
    case "\$(basename "\$f")" in $schedulerLabel.plist) continue;; esac
    echo "PLIST \$f"
    plutil -convert json -o - "\$f" 2>/dev/null | tr -d '\\n'; echo
    echo "PLIST-END"
  done
else
  for t in /etc/systemd/system/*.timer; do
    [ -f "\$t" ] || continue
    s="\${t%.timer}.service"
    grep -q "Written by podship" "\$s" 2>/dev/null || continue
    case "\$(basename "\$t")" in $schedulerUnit.timer) continue;; esac
    echo "TIMER \$t"
    cat "\$t"
    echo "SERVICE"
    cat "\$s"
    echo "TIMER-END"
  done
fi
''';

/// A per-environment agent found on a machine.
class LegacyUnit {
  LegacyUnit({
    required this.name,
    required this.file,
    required this.job,
    required this.times,
  });

  /// The launchd label or the systemd unit name.
  final String name;

  /// The plist or the timer file.
  final String file;

  /// The job it becomes.
  final ScheduledJob job;

  /// When it ran (`HH:MM`), for the report.
  final List<String> times;

  @override
  String toString() => '$name (${times.join(', ')}) → ${job.id}';
}

/// Reads the output of [legacyScanScript]. [registry] gives a backup unit
/// its project and environment.
List<LegacyUnit> parseLegacyUnits(String out, Registry registry) {
  final units = <LegacyUnit>[];
  final lines = const LineSplitter().convert(out);
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    if (line.startsWith('PLIST ')) {
      final file = line.substring(6).trim();
      final body = StringBuffer();
      i++;
      while (i < lines.length && lines[i] != 'PLIST-END') {
        body.write(lines[i]);
        i++;
      }
      final u = _fromPlist(file, body.toString(), registry);
      if (u != null) units.add(u);
    } else if (line.startsWith('TIMER ')) {
      final file = line.substring(6).trim();
      final timer = StringBuffer(), service = StringBuffer();
      var inService = false;
      i++;
      while (i < lines.length && lines[i] != 'TIMER-END') {
        if (lines[i] == 'SERVICE') {
          inService = true;
        } else {
          (inService ? service : timer).writeln(lines[i]);
        }
        i++;
      }
      final u = _fromSystemd(
        file,
        timer.toString(),
        service.toString(),
        registry,
      );
      if (u != null) units.add(u);
    }
    i++;
  }
  return units;
}

LegacyUnit? _fromPlist(String file, String json, Registry registry) {
  Map m;
  try {
    final j = jsonDecode(json);
    if (j is! Map) return null;
    m = j;
  } catch (_) {
    return null;
  }
  final label = '${m['Label'] ?? p.basenameWithoutExtension(file)}';
  final args = [
    for (final a in (m['ProgramArguments'] as List?) ?? const []) '$a',
  ];
  final path = ((m['EnvironmentVariables'] as Map?)?['PATH'] as String?);
  final cal = m['StartCalendarInterval'];
  final times = <String>[
    for (final c in cal is List ? cal : [?cal])
      if (c is Map)
        '${(c['Hour'] ?? 0).toString().padLeft(2, '0')}:${(c['Minute'] ?? 0).toString().padLeft(2, '0')}',
  ];
  if (label.startsWith('dev.podship.backup.')) {
    // /bin/bash <lib>/backup.sh <etc>/<unit>.conf
    final conf = args.where((a) => a.endsWith('.conf')).firstOrNull;
    final script = args.where((a) => a.endsWith('backup.sh')).firstOrNull;
    final entry = registry.entries.values
        .where((e) => e.backupUnit == label)
        .firstOrNull;
    final (project, env) = entry != null
        ? (entry.project, entry.env)
        : _projectEnvFromComment(json) ?? ('', '');
    if (project.isEmpty || conf == null) return null;
    return LegacyUnit(
      name: label,
      file: file,
      times: times,
      job: ScheduledJob(
        kind: JobKind.backup,
        project: project,
        env: env,
        script: script,
        conf: conf,
        log: (m['StandardOutPath'] as String?),
        path: path,
        note: 'migrated from $label (${times.join(', ')})',
      ),
    );
  }
  if (label.startsWith('dev.podship.pull.')) {
    // dev.podship.pull.<project>.<env>: podship backup pull --env <env> --yes
    final rest = label.substring('dev.podship.pull.'.length).split('.');
    if (rest.length < 2) return null;
    final env = rest.last;
    final project = rest.sublist(0, rest.length - 1).join('.');
    final envArg = args.indexOf('--env');
    return LegacyUnit(
      name: label,
      file: file,
      times: times,
      job: ScheduledJob(
        kind: JobKind.pull,
        project: project,
        env: envArg >= 0 && envArg + 1 < args.length ? args[envArg + 1] : env,
        projectDir: m['WorkingDirectory'] as String?,
        path: path,
        note: 'migrated from $label (${times.join(', ')})',
      ),
    );
  }
  return null;
}

(String, String)? _projectEnvFromComment(String text) {
  final m = RegExp(
    r'backup of ([A-Za-z0-9_-]+)/([A-Za-z0-9_-]+)',
  ).firstMatch(text);
  return m == null ? null : (m[1]!, m[2]!);
}

LegacyUnit? _fromSystemd(
  String file,
  String timer,
  String service,
  Registry registry,
) {
  final name = p.basenameWithoutExtension(file);
  final exec = RegExp(
    r'^ExecStart=(.*)$',
    multiLine: true,
  ).firstMatch(service)?[1]?.trim();
  if (exec == null || !exec.contains('backup.sh')) return null;
  final parts = exec.split(RegExp(r'\s+'));
  final cal =
      RegExp(
        r'^OnCalendar=(.*)$',
        multiLine: true,
      ).firstMatch(timer)?[1]?.trim() ??
      '';
  final t = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(cal);
  final times = [
    if (t != null)
      '${t[1]!.padLeft(2, '0')}:${t[2]}${cal.contains(' ') && cal.split(' ').length > 2 ? ' ${cal.split(' ').last}' : ''}',
  ];
  final entry = registry.entries.values
      .where((e) => e.backupUnit == name)
      .firstOrNull;
  final (project, env) = entry != null
      ? (entry.project, entry.env)
      : _projectEnvFromComment(service) ?? ('', '');
  if (project.isEmpty) return null;
  final pathLine = RegExp(
    r'^Environment=PATH=(.*)$',
    multiLine: true,
  ).firstMatch(service)?[1];
  return LegacyUnit(
    name: name,
    file: file,
    times: times,
    job: ScheduledJob(
      kind: JobKind.backup,
      project: project,
      env: env,
      script: parts.first,
      conf: parts.length > 1 ? parts[1] : null,
      path: pathLine,
      note: 'migrated from $name.timer (${times.join(', ')})',
    ),
  );
}

/// Turns the legacy units off: launchd agents are booted out and their
/// plists renamed `.migrated-by-podship`; systemd timers are disabled and
/// their files renamed the same way. [replaces] are older units from
/// `backup.replaces` that get the same treatment (`.disabled-by-podship`).
String retireLegacyScript(
  List<LegacyUnit> units, {
  List<String> replaces = const [],
  required bool macos,
}) {
  final b = StringBuffer();
  if (macos) {
    for (final u in units) {
      b.writeln(
        'launchctl bootout gui/\$(id -u)/${shq(u.name)} 2>/dev/null || true',
      );
      b.writeln(
        '[ -f ${shq(u.file)} ] && mv -f ${shq(u.file)} ${shq('${u.file}.migrated-by-podship')} && echo "retired ${u.name}" || true',
      );
    }
    for (final old in replaces) {
      b.writeln(
        'launchctl bootout gui/\$(id -u)/${shq(old)} 2>/dev/null || true',
      );
      b.writeln('f="\$HOME/Library/LaunchAgents/"${shq('$old.plist')}');
      b.writeln(
        '[ -f "\$f" ] && mv -f "\$f" "\$f.disabled-by-podship" && echo "disabled $old" || true',
      );
    }
  } else {
    for (final u in units) {
      b.writeln(
        'systemctl disable --now ${shq('${u.name}.timer')} 2>/dev/null || true',
      );
      b.writeln(
        'for f in ${shq('${u.name}.timer')} ${shq('${u.name}.service')}; do [ -f /etc/systemd/system/\$f ] && mv -f /etc/systemd/system/\$f /etc/systemd/system/\$f.migrated-by-podship || true; done',
      );
      b.writeln('echo "retired ${u.name}"');
    }
    for (final old in replaces) {
      b.writeln(
        'systemctl disable --now ${shq('$old.timer')} 2>/dev/null || true',
      );
    }
    if (units.isNotEmpty || replaces.isNotEmpty) {
      b.writeln('systemctl daemon-reload');
    }
  }
  if (b.isEmpty) b.writeln('echo "no per-environment agents to retire"');
  return b.toString();
}
