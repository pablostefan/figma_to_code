import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:figma2dart/src/brief.dart';
import 'package:figma2dart/src/component_brief.dart';
import 'package:figma2dart/src/export.dart';
import 'package:figma2dart/src/mappings.dart';
import 'package:figma2dart/src/references.dart';
import 'package:figma2dart/src/resolve.dart';
import 'package:test/test.dart';

// Mapeamentos reais do POC, no repositório irmão `design_system` (precisam de `flutter pub get` lá).
const mappingsDir = '../../design_system/carteira_ds_figma';

Json fixture(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Json;

void main() {
  late MappingSet maps;
  setUpAll(() async => maps = await loadMappings(mappingsDir));

  test('lê os 13 mapeamentos de componente', () {
    expect(maps.components, hasLength(13)); // Avatar tem duas funções (when type)
    expect(maps.components.firstWhere((m) => m.name == 'Avatar').key, '4a1bb73f19680e77a1be870a2630949e0033bddc');
  });

  group('Login (export do plugin, IR 1.1)', () {
    late ResolvedScreen login;
    setUpAll(() => login = Resolver(maps).screen(fixture('login.ir.json')));

    ResolvedInstance byLabel(String text) => login.instances.firstWhere((i) => i.code.contains("'$text'"));

    test('todas as instâncias do DS viram código', () {
      expect(login.instances.map((i) => i.status), everyElement('mapped'));
      expect(login.instances, hasLength(5));
    });

    test('Input em state=error: helper vai para errorText, ícone e ação exposta resolvidos', () {
      final senha = byLabel('Senha').code;
      expect(senha, contains("errorText: 'Senha incorreta. Tente novamente.'"));
      expect(senha, contains('helper: null'));
      expect(senha, contains('leadingIcon: DsIconName.lock'));
      expect(senha, contains('trailing: DsIconButton('));
      expect(senha, contains('icon: DsIconName.eye'));
      expect(senha, contains('variant: DsIconButtonVariant.ghost'));
    });

    test('Button: variant, ternário do ícone e onPressed guiado', () {
      final entrar = byLabel('Entrar');
      expect(entrar.code, contains('variant: DsButtonVariant.primary'));
      expect(entrar.code, contains('leftIcon: null'));
      expect(entrar.code, contains('/* f2d:guided'));
      final g = login.guided.firstWhere((g) => entrar.guided.contains(g.id));
      expect(g.part, 'onPressed');
      expect(g.figma['label'], 'Entrar');
    });

    test('Checkbox checked=true vira value: true', () {
      expect(byLabel('Lembrar de mim').code, contains('value: true'));
    });

    test('override de estilo fora da API fica registrado', () {
      final overrides = byLabel('Senha').overrides;
      expect(overrides.where((o) => o['kind'] == 'style').single['node'], 'field/leadingIcon/Vector');
    });

    test('brief traz código, decisões e regras', () {
      final md = brief(login);
      expect(md, contains("label: 'Entrar'"));
      expect(md, contains('## Decisões (f2d:guided)'));
      expect(md, contains('[obrigatório] Ligar o campo ao estado da tela'));
    });
  });

  group('Fluxo (export MCP, IR 1.0)', () {
    test('Dashboard: instâncias expostas lidas com f.nested', () {
      final dashboard = Resolver(maps).screen(fixture('flow.ir.json'), screen: '02 · Dashboard');
      final codes = dashboard.instances.map((i) => i.code).join('\n');
      expect(codes, contains("initials: 'AS'"));
      expect(codes, contains("delta: '+2,4% este mês'"));
      expect(codes, contains('direction: DsTransactionDirection.'));
    });

    test('componentes locais viram placeholder com id e key', () {
      final transferir = Resolver(maps).screen(fixture('flow.ir.json'), screen: '03 · Transferir');
      final locals = transferir.instances.where((i) => i.status == 'placeholder').toList();
      expect(locals.map((i) => i.component), containsAll(['TopBar', 'ContactItem']));
      expect(locals.first.code, matches(RegExp(r'f2d:placeholder component \w+ \(\d+:\d+, key [0-9a-f]{8}\)')));
      expect(locals.first.code, contains('Placeholder()'));
    });

    test('componente fora do DS ganha brief de construção com API, estrutura e usos', () {
      final transferir = Resolver(maps).screen(fixture('flow.ir.json'), screen: '03 · Transferir');
      expect(transferir.components.map((c) => c.name), ['TopBar', 'ContactItem']);
      final contact = transferir.components.last;
      expect(contact.uses, hasLength(3));
      final md = componentBrief(contact);
      expect(md, contains('`widgets/contact_item.dart`'));
      // As iniciais do Avatar exposto mudam em cada uso: viram parâmetro, não o 'AS' do exemplo.
      expect(
        md,
        contains(
          'const ContactItem({required this.name, required this.detail, required this.avatarInitials, super.key});',
        ),
      );
      expect(md, contains('prop `initials` (muda nos usos: AS, BL, CD)'));
      expect(md, contains('**exposta**: os valores mudam em cada uso'));
      expect(md, contains('expostas `{"Avatar":{"icon":"DsIconName.arrowDownLeft","initials":"BL"'));
      expect(md, contains("`Avatar`: DS `DsAvatar.initials('AS', size: DsAvatarSize.md)`"));
      expect(
        md,
        contains('HORIZONTAL gap DsSpacing.md padding vertical DsSpacing.md, horizontal 0'),
      ); // tokens já em Dart
      expect(md, contains('override `Vector`: cor do traço DsColors.textSecondary')); // legível, não JSON
      expect(md, contains('override `Vector`: cor do traço DsColors.textSecondary · 20×20')); // tamanho do Figma
      expect(md, contains('texto ← prop `name` · DsTextStyles.label DsColors.textPrimary'));
      expect(md, contains('"name":"Bruno Lima"'));
      expect(brief(transferir), contains('[ContactItem](components/contact_item/BRIEF.md)'));
    });

    test('tela inexistente explica quais existem', () {
      expect(
        () => Resolver(maps).screen(fixture('flow.ir.json'), screen: 'Perfil'),
        throwsA(isA<ResolveError>().having((e) => e.message, 'message', contains('02 · Dashboard'))),
      );
    });
  });

  test('componente complete: só as seções das partes decididas na tela, pela convenção de nome do doc', () {
    final login = Resolver(maps).screen(fixture('login.ir.json'));
    final md = brief(login);
    final button = md.substring(md.indexOf('### Button'));
    expect(button, contains('Doc: carteira_ds_figma/docs/ds_button.md'));
    expect(button, contains('#### onPressed'));
    expect(button, contains('#### Erros comuns'));
    expect(md, contains('#### semanticLabel'));
    expect(md, contains('(online, sem `source`: abra se precisar)')); // Doc.link do Input
  });

  test('componente complete sem regra nem decisão não aparece na seção de componentes', () {
    final s = Resolver(maps).screen(
      screenWith([
        instanceNode(key: badgeKey, component: 'Badge', props: {'label': 'Pix', 'tone': 'success'}),
      ]),
    );
    expect(brief(s), isNot(contains('## Componentes desta tela')));
  });

  test('doc e exemplo que existem entram no brief; o que sumiu é avisado, sem quebrar', () {
    // Pasta própria: o teste não depende do que existe hoje nos pacotes do Carteira (o sample app muda).
    final root = Directory.systemTemp.createTempSync('f2d_refs');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/carteira_ds_figma/docs/ds_transaction_list.md')
      ..createSync(recursive: true)
      ..writeAsStringSync('# Lista\n\nAs linhas vêm dos dados da tela.\n');
    File('${root.path}/carteira_ds_examples/lib/transaction_list_example.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('class TransactionListExample {}\n');
    final list = maps.components.firstWhere((m) => m.name == 'TransactionList');
    final md = References(root.path).render(list, {'x'});
    expect(md, contains('As linhas vêm dos dados da tela.'));
    expect(md, contains('class TransactionListExample {}'));
    expect(md, contains('`_DashboardPageState.build` (arquivo não encontrado)')); // o uso real no sample app
    expect(md, isNot(contains('**(não encontrado')));
  });

  test('doc sem seções ## entra inteiro como Geral', () {
    final dir = Directory.systemTemp.createTempSync('f2d_doc');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/docs/ds_badge.md')
      ..createSync(recursive: true)
      ..writeAsStringSync('# Badge\n\nTom pelo status da transação, nunca pela cor.\n');
    final badge = maps.components.firstWhere((m) => m.name == 'Badge');
    final md = References(dir.path).render(badge, {'label'});
    expect(md, contains('Tom pelo status da transação'));
    expect(md, isNot(contains('# Badge')));
  });

  test('zip: caminho de imagem que sai da pasta da tarefa não é escrito', () {
    final root = Directory.systemTemp.createTempSync('f2d_slip');
    addTearDown(() => root.deleteSync(recursive: true));
    final out = Directory('${root.path}/task')..createSync();
    final export = Export({}, {'../fora.png': Uint8List(1), 'images/ok.png': Uint8List(1)});
    final copied = export.copyImages(
      ResolvedScreen(screen: 'T', state: 's', frameId: '1:1', instances: [], guided: [], image: '../fora.png'),
      out,
    );
    expect(copied, isEmpty);
    expect(File('${root.path}/fora.png').existsSync(), isFalse);
  });

  test('zip com extensão maiúscula e brief só cita a imagem que foi copiada', () {
    final dir = Directory.systemTemp.createTempSync('f2d_upper');
    addTearDown(() => dir.deleteSync(recursive: true));
    final zip = File('test/fixtures/flow.plugin.zip').copySync('${dir.path}/FLOW.ZIP');
    final s = Resolver(maps).screen(Export.read(zip.path).ir, screen: '04 · Confirmar');
    expect(brief(s, images: {}), contains('Referência visual: o PNG da tela no export do plugin'));
    expect(brief(s, images: {s.image!}), contains('`images/screens/04_Confirmar--7-382.png`'));
  });

  test('zip do plugin: lê o export.json e copia só os PNGs citados no brief', () {
    final export = Export.read('test/fixtures/flow.plugin.zip');
    final s = Resolver(maps).screen(export.ir, screen: '04 · Confirmar');
    expect(s.image, 'images/screens/04_Confirmar--7-382.png');
    final summary = s.components.firstWhere((c) => c.name == 'SummaryRow');
    expect(componentBrief(summary), contains('`../../images/summaryrow/SummaryRow--6-102.png`'));
    expect(componentBrief(summary), contains('stroke DsColors.border baixo 1 (outros 0)'));

    final dir = Directory.systemTemp.createTempSync('f2d_zip');
    addTearDown(() => dir.deleteSync(recursive: true));
    export.copyImages(s, dir);
    final copied = dir.listSync(recursive: true).whereType<File>().map((f) => f.path.substring(dir.path.length + 1));
    expect(
      copied,
      unorderedEquals([
        s.image,
        for (final c in s.components) ((c.definition!['variants'] as List).single as Json)['image'],
      ]),
    );
  });

  test('Avatar: when escolhe a função pelo type e o helper _size é avaliado no lugar', () {
    Json avatar(String type) => screenWith([
      instanceNode(
        key: avatarKey,
        component: 'Avatar',
        props: {
          'type': type,
          'size': 'md',
          'initials': 'PS',
          'icon': {
            'variant': {'name': 'arrow-up-right'},
          },
        },
      ),
    ]);
    expect(
      Resolver(maps).screen(avatar('initials')).instances.single.code,
      "DsAvatar.initials('PS', size: DsAvatarSize.md)",
    );
    expect(
      Resolver(maps).screen(avatar('icon')).instances.single.code,
      'DsAvatar.icon(DsIconName.arrowUpRight, size: DsAvatarSize.md)',
    );
  });

  group('regressões da auditoria', () {
    test('mapeamento que não compila é erro, não some calado', () async {
      final dir = Directory.systemTemp.createTempSync('f2d_broken');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/lib/connect/broken.figma.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync("int x = 'a';");
      await expectLater(loadMappings(dir.path), throwsA(isA<StateError>()));
    });

    test('override de conteúdo vira gap com o valor, no json e no brief', () {
      final s = Resolver(maps).screen(
        screenWith([
          instanceNode(
            key: badgeKey,
            component: 'Badge',
            props: {'label': 'Pix', 'tone': 'success'},
            overrides: [
              {
                'node': 'label',
                'fields': ['characters'],
                'values': {'characters': 'Ver extrato'},
              },
            ],
          ),
        ]),
      );
      final override = s.instances.single.overrides.single;
      expect(override['kind'], 'content');
      expect(override['values'], {'characters': 'Ver extrato'});
      expect(brief(s), allOf(contains('f2d:gap** override de conteúdo'), contains('Ver extrato')));
    });

    test('variant sem mapeamento derruba só a instância, que vira gap com o motivo', () {
      final s = Resolver(maps).screen(
        screenWith([
          instanceNode(key: buttonKey, component: 'Button', props: {...buttonProps, 'variant': 'danger'}),
          instanceNode(key: badgeKey, component: 'Badge', props: {'label': 'Pix', 'tone': 'success'}),
        ]),
      );
      final [button, badge] = s.instances;
      expect(button.status, 'gap');
      expect(button.error, contains('variant variant=danger'));
      expect(button.code, contains('Placeholder()'));
      expect(s.guided, isEmpty, reason: 'decisões da instância que falhou são descartadas');
      expect(badge.status, 'mapped');
    });

    test('reusar o Resolver não mistura decisões entre telas', () {
      final r = Resolver(maps);
      r.screen(fixture('login.ir.json'));
      final sucesso = r.screen(fixture('flow.ir.json'), screen: '05 · Sucesso');
      expect(sucesso.guided.first.id, 'G1');
      expect(sucesso.guided.every((g) => sucesso.instances.any((i) => i.guided.contains(g.id))), isTrue);
    });

    test('instância escondida no Figma não entra', () {
      final s = Resolver(maps).screen(
        screenWith([
          instanceNode(key: badgeKey, component: 'Badge', props: {'label': 'Erro', 'tone': 'danger'}, visible: false),
          instanceNode(key: badgeKey, component: 'Badge', props: {'label': 'Pix', 'tone': 'success'}),
        ]),
      );
      expect(s.instances.single.code, contains("'Pix'"));
    });

    test('export sem telas ou de versão desconhecida explica o problema', () {
      expect(
        () => Resolver(maps).screen(
          jsonDecode(File('../figma_plugin/examples/component-transaction-item.ir.json').readAsStringSync()) as Json,
        ),
        throwsA(isA<ResolveError>().having((e) => e.message, 'message', contains('kind=component'))),
      );
      expect(
        () => Resolver(maps).screen({...screenWith([]), 'irVersion': '9.0.0'}),
        throwsA(isA<ResolveError>().having((e) => e.message, 'message', contains('9.0.0'))),
      );
    });

    test('ícone de set com várias variants ou de um componente por ícone', () {
      String icon(Object swap) => Resolver(maps)
          .screen(
            screenWith([
              instanceNode(
                key: buttonKey,
                component: 'Button',
                props: {...buttonProps, 'showLeftIcon': true, 'leftIcon': swap},
              ),
            ]),
          )
          .instances
          .single
          .code;
      expect(
        icon({
          'componentName': 'Icon',
          'variant': {'name': 'mail', 'size': '24'},
        }),
        contains('DsIconName.mail'),
      );
      expect(icon({'componentName': 'Icons/arrow-up-right'}), contains('DsIconName.arrowUpRight'));
      // Ícone que não existe no enum: o componente fica, com um valor provisório e o TODO para o dev.
      final missing = icon({
        'componentName': 'Icon',
        'variant': {'name': 'cartao-novo'},
      });
      expect(missing, startsWith('DsButton('));
      expect(
        missing,
        contains('/* TODO(f2d): ícone "cartao-novo" do Figma não existe em DsIconName */ DsIconName.home'),
      );
    });

    test('TransactionList (partial): título do Figma, linhas e ação viram decisões, norte e docs no brief', () {
      final s = Resolver(maps).screen(
        screenWith([
          instanceNode(
            key: transactionListKey,
            component: 'TransactionList',
            props: {'title': 'Últimas', 'showAction': true},
          ),
        ]),
      );
      final i = s.instances.single;
      expect(i.status, 'mapped');
      expect(i.code, contains("title: 'Últimas'"));
      expect(s.guided.map((g) => g.part), ['onSeeAll', 'items']);
      final md = brief(s);
      expect(md, contains('Norte: Seção de transações'));
      // partial: doc inteiro, 1 exemplo `code` com o código e 1 `usage`.
      expect(md, contains('Doc: carteira_ds_figma/docs/ds_transaction_list.md — de onde vêm as linhas e quantas'));
      expect(md, contains('#### items'));
      expect(md, contains('class TransactionListExample extends StatelessWidget'));
      expect(md, contains("String actionLabel = 'Ver todas', // Action label."));
      expect(md, contains('Uso real (contexto: não copie a lógica de negócio)'));
      expect(md, isNot(contains('Dados do Figma')));
    });

    test('Template / Extrato (sketch): placeholder na tela e brief de montagem com a API do widget', () {
      final s = Resolver(maps).screen(
        screenWith([
          instanceNode(
            key: statementKey,
            component: 'Template / Extrato',
            props: {'title': 'Extrato', 'showSummary': true},
          ),
        ]),
      );
      final i = s.instances.single;
      expect(i.status, 'sketch');
      expect(i.code, startsWith('/* f2d:sketch Template / Extrato → DsStatementTemplate */ const SizedBox('));
      final task = s.components.single;
      expect((task.kind, task.folder), ('sketch', 'template_extrato'));

      final screen = brief(s);
      expect(screen, contains('Montar: [brief](components/template_extrato/BRIEF.md)'));
      expect(screen, contains('- [Template / Extrato](components/template_extrato/BRIEF.md) → `DsStatementTemplate`'));
      expect(screen, isNot(contains('## Fora do mapeamento')));
      // Norte, docs e exemplo ficam só no brief do sketch.
      expect(screen, isNot(contains('class StatementExample')));
      expect(screen, isNot(contains('### Template / Extrato (sketch)')));

      final md = componentBrief(task, references: s.references[task.name]);
      expect(md, contains('# Montar: Template / Extrato → `DsStatementTemplate`'));
      expect(md, contains('Corpo da tela de extrato.'));
      expect(md, contains('required List<DsStatementDay> days, // Day groups, newest first.'));
      expect(md, contains('class DsStatementDay {'));
      expect(md, contains('- Props do Figma: `{"title":"Extrato","showSummary":true}`'));
      expect(md, contains('#### Por que é sketch'));
      expect(md, contains('class StatementExample extends StatelessWidget'));
    });

    test('FigmaConnect.sketch numa função é erro: o sketch anota um typedef', () async {
      final dir = Directory.systemTemp.createTempSync('f2d_sketch_fn');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/pubspec.yaml').writeAsStringSync('name: x\n');
      File('${dir.path}/lib/connect/x.figma.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
import 'package:figma_connect/figma_connect.dart';
import 'package:flutter/widgets.dart';

@FigmaConnect.sketch(key: 'k', name: 'X', guide: 'g')
Widget x(FigmaProps f) => const SizedBox();
''');
      await expectLater(
        loadMappings(dir.path, packageConfig: '$mappingsDir/.dart_tool/package_config.json'),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('anota um typedef'))),
      );
    });

    test('instância sem componente principal vira gap, não um componente a construir', () {
      Json missing(String name) {
        final node = instanceNode(key: '', component: name, props: {});
        return {
          ...node,
          'instance': {...node['instance'] as Json, 'remote': false},
        };
      }

      final s = Resolver(maps).screen(screenWith([missing('Banner'), missing('Chart')]));
      expect(s.instances.map((i) => i.status), ['gap', 'gap']);
      expect(s.instances.first.error, 'instância sem componente principal no Figma');
      expect(s.components, isEmpty);
    });

    test('dois componentes locais com o mesmo nome ganham pastas e classes diferentes', () {
      Json local(String key) {
        final node = instanceNode(key: key, component: 'Header', props: {});
        return {
          ...node,
          'instance': {...node['instance'] as Json, 'remote': false},
        };
      }

      final s = Resolver(maps).screen(screenWith([local('aaaaaaaa11'), local('bbbbbbbb22')]));
      expect(s.components.map((c) => c.folder), ['header', 'header_bbbbbb']);
      final md = brief(s);
      expect(md, contains('[Header](components/header_bbbbbb/BRIEF.md)'));
      expect(componentBrief(s.components.last), contains('classe `HeaderBbbbbb`'));
    });

    test('componente local dentro de outro: dependência primeiro, link no brief, variant vira enum', () {
      Json local(String key, String name) => {
        ...instanceNode(key: key, component: name, props: {}),
        'instance': {...instanceNode(key: key, component: name, props: {})['instance'] as Json, 'remote': false},
      };
      final ir = {
        ...screenWith([local('outer', 'Card Row')]),
        'components': [
          {
            'id': '5:1',
            'key': 'outer',
            'name': 'Card Row',
            'props': {
              'size': {
                'type': 'VARIANT',
                'default': 'sm',
                'options': ['sm', 'lg'],
              },
            },
            'variants': [
              {
                'id': '5:1',
                'name': 'size=sm',
                'props': {'size': 'sm'},
                'tree': {
                  'id': '5:1',
                  'type': 'COMPONENT',
                  'name': 'Card Row',
                  'children': [local('inner', 'Tag')],
                },
              },
            ],
          },
          {'id': '5:9', 'key': 'inner', 'name': 'Tag', 'props': <String, Object>{}, 'variants': <Object>[]},
        ],
      };
      final s = Resolver(maps).screen(ir);
      expect(s.components.map((c) => c.name), ['Tag', 'Card Row']);
      final md = componentBrief(s.components.last);
      expect(md, contains('[brief](../tag/BRIEF.md)'));
      expect(md, contains('this.size = CardRowSize.sm'));
      expect(md, contains('enum CardRowSize { sm, lg }'));
      expect(componentBrief(s.components.first), contains('Usado só dentro de outros componentes locais.'));
    });

    test('esqueleto @FigmaScreen no brief da tela; imagem e vetor viram placeholder com TODO', () {
      final s = Resolver(maps).screen(
        screenWith([
          {
            'id': '5:1',
            'type': 'FRAME',
            'name': 'banner',
            'size': {'width': 342, 'height': 120},
            'style': {
              'fills': [
                {'type': 'IMAGE', 'scaleMode': 'FILL'},
              ],
            },
          },
          {
            'id': '5:2',
            'type': 'GROUP',
            'name': 'ilustracao',
            'size': {'width': 80, 'height': 80},
            'children': [
              {'id': '5:3', 'type': 'VECTOR', 'name': 'a'},
              {'id': '5:4', 'type': 'BOOLEAN_OPERATION', 'name': 'b'},
            ],
          },
        ]),
      );
      final md = brief(s);
      expect(md, contains('## Esqueleto da tela (@FigmaScreen)'));
      expect(md, contains('backgroundColor: DsColors.bg'));
      expect(
        md,
        contains(
          'imagem → `/* TODO(f2d): imagem do Figma "banner" (5:1), asset ainda não exportado */ '
          'const SizedBox(width: 342, height: 120, child: Placeholder())`',
        ),
      );
      expect(md, contains('`ilustracao`: vetor → `/* TODO(f2d): vetor do Figma "ilustracao" (5:2)'));
      expect(md, isNot(contains('`a`:')));
      // Componente local que é só vetor (um logo) vira um placeholder só, não um por pedaço.
      final logo = componentBrief(
        ComponentTask(
          name: 'Logo',
          key: 'logo',
          definition: {
            'id': '8:1',
            'props': <String, Object>{},
            'variants': [
              {
                'id': '8:1',
                'name': 'Logo',
                'props': <String, Object>{},
                'tree': {
                  'id': '8:1',
                  'type': 'COMPONENT',
                  'name': 'Logo',
                  'children': [
                    {'id': '8:2', 'type': 'VECTOR', 'name': 'p1'},
                    {'id': '8:3', 'type': 'VECTOR', 'name': 'p2'},
                  ],
                },
              },
            ],
          },
          variants: const {},
          uses: const [],
          guided: const [],
          devNotes: const {},
        )..folder = 'logo',
      );
      expect('TODO(f2d)'.allMatches(logo).length, 1);
    });

    test('sketch dentro de componente local ganha tarefa, e o brief do componente aponta para ela', () {
      final local = instanceNode(key: 'local1', component: 'Statement Card', props: {});
      final ir = {
        ...screenWith([
          {
            ...local,
            'instance': {...local['instance'] as Json, 'remote': false},
          },
        ]),
        'components': [
          {
            'id': '6:1',
            'key': 'local1',
            'name': 'Statement Card',
            'props': <String, Object>{},
            'variants': [
              {
                'id': '6:1',
                'name': 'Statement Card',
                'props': <String, Object>{},
                'tree': {
                  'id': '6:1',
                  'type': 'COMPONENT',
                  'name': 'Statement Card',
                  'children': [
                    instanceNode(key: statementKey, component: 'Template / Extrato', props: {'title': 'E'}),
                  ],
                },
              },
            ],
          },
        ],
      };
      final s = Resolver(maps).screen(ir);
      expect(s.components.map((c) => (c.name, c.kind)), [
        ('Statement Card', 'build'),
        ('Template / Extrato', 'sketch'),
      ]);
      final card = componentBrief(s.components.first, folders: (i) => taskOf(s, i)?.folder);
      expect(card, contains('DS **Template / Extrato** a montar → [brief](../template_extrato/BRIEF.md)'));
      expect(componentBrief(s.components.last), contains('dentro do componente local **Statement Card**'));
    });

    test('dois mapeamentos empatados para a mesma instância é erro', () {
      final badge = maps.components.firstWhere((m) => m.name == 'Badge');
      final s = Resolver(MappingSet([...maps.components, badge])).screen(
        screenWith([
          instanceNode(key: badgeKey, component: 'Badge', props: {'label': 'Pix', 'tone': 'success'}),
        ]),
      );
      expect(s.instances.single.error, contains('dois mapeamentos'));
    });
  });
}

const avatarKey = '4a1bb73f19680e77a1be870a2630949e0033bddc';
const transactionListKey = 'd9952bc57f16a4305a89962f466c91b09259b275';
const statementKey = 'e5eab15a82d946ba1d45e7ba5569b844db450418';
const badgeKey = 'f5c999bbdd2c2b543fd66177465fe4a300b30e9a';
const buttonKey = 'cc4d255d4c889786852f8ba4b57a714a4efd07ca';
const buttonProps = <String, Object>{
  'label': 'Entrar',
  'showLeftIcon': false,
  'leftIcon': 'plus',
  'variant': 'primary',
  'size': 'md',
  'state': 'default',
};

/// Export IR mínimo com uma tela `T` contendo [children].
Json screenWith(List<Json> children) => {
  'irVersion': '1.2.0',
  'kind': 'screen',
  'screens': [
    {
      'name': 'T',
      'states': [
        {
          'state': 'default',
          'id': '1:1',
          'frameName': 'T',
          'tree': {'id': '1:1', 'type': 'FRAME', 'name': 'T', 'children': children},
        },
      ],
    },
  ],
};

var _ids = 1;

Json instanceNode({
  required String key,
  required String component,
  required Json props,
  List<Json> overrides = const [],
  bool visible = true,
  bool remote = true,
}) => {
  'id': '9:${_ids++}',
  'type': 'INSTANCE',
  'name': component,
  if (!visible) 'visible': false,
  'size': {'width': 40, 'height': 40},
  'instance': {
    'componentKey': key,
    'componentName': component,
    'remote': remote,
    'props': props,
    'exposed': <Object>[],
    'overrides': overrides,
  },
};
