import 'package:flutter/widgets.dart';

import 'guidance.dart';

/// O que a função anotada pode ler da instância no Figma.
///
/// Só é avaliada pelo gerador, que troca cada chamada pelo valor da instância. Os nomes de prop vêm sem o
/// sufixo `#id` do Figma. Os métodos genéricos tiram o tipo do contexto: `DsIcon(f.icon('name'))` resolve `T`.
abstract interface class FigmaProps {
  /// Prop TEXT.
  String text(String name);

  /// Prop BOOLEAN.
  bool boolean(String name);

  /// Prop VARIANT, traduzida por [values] (valor do Figma → valor no código).
  T variant<T>(String name, Map<String, T> values);

  /// INSTANCE_SWAP de ícone, resolvido pela tabela de ícones da política (valor do enum ou constante da classe de
  /// ícones).
  T icon<T>(String name);

  /// INSTANCE_SWAP ou instância exposta, resolvida pelo mapeamento dela.
  Widget instance(String name);

  /// Instância exposta sem mapeamento próprio (ex.: `1. Flag`), para o pai ler as props dela.
  FigmaProps nested(String path);

  /// Área livre de um template, gerada a partir da árvore do Figma.
  Widget slot(String part);

  /// Parte que exige julgamento: o gerador escreve [or] (que compila) e o marcador `f2d:guided` com [guide].
  T guided<T>(String part, {required String guide, required T or, List<Doc> docs, List<Example> examples});
}

/// O que a função anotada com `FigmaScreen` pode ler da tela.
abstract interface class FigmaScreenProps {
  /// Instância na tela do componente de [mapping] (achada pela key da anotação dele, não pelo nome); `null` se a
  /// tela não tiver uma.
  Widget? instance(Widget Function(FigmaProps) mapping);

  /// O resto da árvore gerada.
  Widget body();
}

/// O que a função anotada com `FigmaText` pode ler de um texto do Figma. Os métodos genéricos tiram o tipo do
/// contexto: `type: t.style()` resolve `T` pelo parâmetro do widget.
abstract interface class FigmaTextProps {
  /// O texto: literal na tela; num componente a construir, o parâmetro da prop ligada a ele.
  String text();

  /// O estilo de texto do Figma pelo `TokenTable.textStyles` da política (`AcmeTextType.bodySm`).
  T style<T>();

  /// A cor do texto pelo token (`context.acmeColors.textPrimary`).
  T color<T>();
}

/// O que a função anotada com `FigmaText.rich` pode ler de um texto com trechos em estilos diferentes.
abstract interface class FigmaRichTextProps {
  /// Um item por trecho do Figma, na ordem: [span] recebe o texto, o estilo e a cor daquele trecho.
  List<T> spans<T>(T Function(FigmaTextProps s) span);
}

