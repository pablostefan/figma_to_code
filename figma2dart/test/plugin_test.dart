import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// O plugin do Copilot (`copilot_plugin/`, Agent Plugins 1.0) carrega sem erro: manifesto válido, cada skill com o
/// `name` igual ao da pasta (o VS Code ignora a que não bate, sem avisar) e os links dos agentes para skills que existem.
void main() {
  const root = '../copilot_plugin';

  test('manifesto: schema 1.0 e nome em minúsculas, dígitos, hífen e ponto', () {
    final manifest = jsonDecode(File('$root/plugin.json').readAsStringSync()) as Map<String, Object?>;
    expect(manifest[r'$schema'], 'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json');
    expect(manifest['name'], matches(RegExp(r'^[a-z0-9](?:[a-z0-9.-]{0,62}[a-z0-9])?$')));
  });

  test('lsp: servidor dart com comando e extensões', () {
    final lsp = jsonDecode(File('$root/com.github.copilot/lsp.json').readAsStringSync()) as Map<String, Object?>;
    final dart = (lsp['lspServers'] as Map<String, Object?>)['dart'] as Map<String, Object?>;
    expect(dart['command'], 'dart');
    expect(dart['fileExtensions'], {'.dart': 'dart'});
  });

  test('hooks: versão 1 e scripts que existem no plugin', () {
    final file = File('$root/com.github.copilot/hooks/hooks.json');
    final config = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect(config['version'], 1);
    for (final hook in (config['hooks'] as Map<String, Object?>).values.expand((e) => e as List)) {
      final script = RegExp(r'\$\{PLUGIN_ROOT\}/([^"\s]+)').firstMatch((hook as Map)['bash'] as String)![1];
      expect(File('$root/$script').existsSync(), isTrue, reason: script);
    }
  });

  test('skills: uma pasta por skill, com o name do frontmatter igual ao nome da pasta', () {
    final skills = Directory('$root/skills').listSync().whereType<Directory>().toList();
    expect(skills, isNotEmpty);
    for (final dir in skills) {
      final folder = dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      final skill = File('${dir.path}/SKILL.md').readAsStringSync();
      expect(RegExp(r'^name: (.+)$', multiLine: true).firstMatch(skill)?.group(1), folder, reason: dir.path);
    }
  });

  test('agentes: os links para skills apontam para skills do plugin', () {
    final agents = Directory('$root/com.github.copilot/agents').listSync().whereType<File>().toList();
    expect(agents.map((a) => a.path), everyElement(endsWith('.agent.md')));
    for (final agent in agents) {
      for (final link in RegExp(r'\]\((\.\./\.\./skills/[^)]+)\)').allMatches(agent.readAsStringSync())) {
        expect(File('${agent.parent.path}/${link[1]}').existsSync(), isTrue, reason: '${agent.path} → ${link[1]}');
      }
    }
  });
}
