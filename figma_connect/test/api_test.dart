import 'package:figma_connect/figma_connect.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Widgets falsos no lugar do DS: o teste prova que os mapeamentos de docs/FIGMA_CONNECT.md compilam e inferem tipos.
enum DsIconName { mail, lock }

abstract final class Spacing {
  /// `md` = 12
  static const double md = 12;
}

class Colors {
  const Colors({this.textPrimary = const Color(0xFF111111)});

  /// `text/primary`
  final Color textPrimary;
}

enum DsBadgeTone { neutral, success }

class DsIcon extends StatelessWidget {
  const DsIcon(this.name, {super.key});
  final DsIconName name;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class DsBadge extends StatelessWidget {
  const DsBadge({required this.label, required this.tone, super.key});
  final String label;
  final DsBadgeTone tone;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class ListPage extends StatelessWidget {
  const ListPage({
    required this.title,
    required this.header,
    required this.filters,
    required this.onRefresh,
    this.leading,
    super.key,
  });
  final String title;
  final Widget header;
  final List<Widget> filters;
  final Future<void> Function() onRefresh;
  final DsIconName? leading;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

const badgeConnect = FigmaConnect(key: 'b3e1', name: 'Badge');

@badgeConnect
Widget badge(FigmaProps f) => DsBadge(
  label: f.text('label'),
  tone: f.variant('tone', {'neutral': DsBadgeTone.neutral, 'success': DsBadgeTone.success}),
);

const listConnect = FigmaConnect(
  key: '9f2c',
  name: 'Template / Lista com filtro',
  kind: FigmaKind.template,
  tags: {'list'},
  owner: 'time-ds-core',
  status: Status.deprecated(replacement: 'Template / Lista v2'),
  coverage: Coverage.partial,
  guide: 'Lista paginada.',
  figmaNotes: {
    'state': FigmaNote.derive('O vazio vem de items: []'),
    'Collapse': FigmaNote.ignore('Só visual'),
    'Currency': FigmaNote.map({'Global': null, 'BRL': 'brl'}, hint: 'Global = sem filtro'),
  },
  devNotes: [
    DevNote.must('Não envolver em outro scaffold.', lint: 'acme_single_scaffold'),
    DevNote.prefer('Até 3 chips.'),
  ],
  docs: [
    Doc.path('docs/lista.md', hint: 'Visão geral'),
    Doc.link('https://ds.empresa/paginacao', source: 'docs/paginacao.md', hint: 'Paginação'),
  ],
  examples: [
    Example.code('carteira_ds_examples/lib/lista.dart', symbol: 'ListaBasica', hint: 'Caso padrão'),
    Example.usage('lib/extrato_page.dart', symbol: 'ExtratoPage', repo: 'extrato-app'),
  ],
);

@listConnect
Widget list(FigmaProps f) => ListPage(
  title: f.text('Title'),
  header: f.slot('header'),
  leading: f.boolean('Show icon') ? f.icon('icon') : null,
  filters: f.guided(
    'filters',
    guide: 'Cada Flag exposta vira um chip.',
    docs: const [Doc.path('docs/lista.md', section: 'filters')],
    or: const [],
  ),
  onRefresh: f.guided('onRefresh', guide: 'Só existe no código.', or: () async {}),
);

const sketchConnect = FigmaConnect.sketch(
  key: '7c1d',
  name: 'Template / Extrato',
  kind: FigmaKind.template,
  guide: 'Lista agrupada por dia; cada linha é um Badge.',
  docs: [Doc.path('docs/extrato.md')],
);

@sketchConnect
typedef Extrato = ListPage;

// Componente do app que já existe: só a key e o widget.
@FigmaLocal(key: 'contact-item', name: 'ContactItem')
typedef ContactItemFigma = ListPage;

@FigmaConnect(key: '087d', name: 'Icon', kind: FigmaKind.icon)
Widget icon(FigmaProps f) => DsIcon(f.icon('name'));

@FigmaScreen()
Widget screen(FigmaScreenProps s) => Column(children: [?s.instance(badge), s.body()]);

const policy = FigmaPolicy(
  kinds: {
    FigmaKind.template: KindPolicy(
      require: {Field.guide, Field.docs, Field.exampleCode},
      brief: BriefDepth.full,
      devNotes: [DevNote.must('Sempre dentro de um contexto.')],
    ),
    FigmaKind.icon: KindPolicy(expectedCoverage: Coverage.complete, brief: BriefDepth.none),
  },
  icons: IconTable(values: DsIconName.values, byKey: {'c983': DsIconName.mail}),
  tokens: TokenTable(
    collections: {
      'Spacing': TokenSource(Spacing),
      'Color': TokenSource(Colors, via: 'context.dsColors'),
    },
  ),
  ignored: {'4a7e': 'Anotação de handoff'},
);

void main() {
  test('padrões do FigmaConnect', () {
    expect(badgeConnect.kind, FigmaKind.component);
    expect(badgeConnect.coverage, Coverage.complete);
    expect(badgeConnect.status, Status.stable);
    expect(badgeConnect.figmaNotes, isEmpty);
  });

  test('template parcial guarda o norte tipado', () {
    expect(
      listConnect.status,
      isA<DeprecatedStatus>().having((s) => s.replacement, 'replacement', 'Template / Lista v2'),
    );
    expect(listConnect.figmaNotes['state'], isA<DeriveNote>());
    expect(listConnect.figmaNotes['Collapse'], isA<IgnoreNote>());
    expect(listConnect.figmaNotes['Currency'], isA<MapNote>().having((n) => n.values['Global'], 'Global', isNull));
    expect(listConnect.devNotes.first, isA<MustNote>().having((n) => n.lint, 'lint', 'acme_single_scaffold'));
    expect(listConnect.docs.map((d) => d.hint), ['Visão geral', 'Paginação']);
    expect(listConnect.docs.last, isA<LinkDoc>().having((d) => d.source, 'source', 'docs/paginacao.md'));
    expect(listConnect.examples.first.symbol, 'ListaBasica');
    expect(listConnect.examples.last, isA<UsageExample>().having((e) => e.repo, 'repo', 'extrato-app'));
  });

  test('sketch fixa a cobertura e exige o norte', () {
    expect(sketchConnect.coverage, Coverage.sketch);
    expect(sketchConnect.guide, isNotEmpty);
    expect(sketchConnect.kind, FigmaKind.template);
  });

  test('FigmaLocal: só key e nome; norte opcional', () {
    const local = FigmaLocal(key: 'k', name: 'ContactItem');
    expect((local.key, local.name, local.guide), ('k', 'ContactItem', null));
  });

  test('política por tipo e tabela de ícones', () {
    expect(policy.tokens!.collections['Color']!.via, 'context.dsColors');
    expect(policy.kinds[FigmaKind.template]!.require, contains(Field.exampleCode));
    expect(policy.kinds[FigmaKind.icon]!.brief, BriefDepth.none);
    expect(policy.icons!.byKey['c983'], DsIconName.mail);
  });
}
