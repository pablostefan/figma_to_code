import 'package:figma2dart/src/names.dart';
import 'package:test/test.dart';

void main() {
  test('acento vira a letra sem acento; número e vazio ganham nome válido', () {
    expect(pascalCase('Cartão de Crédito'), 'CartaoDeCredito');
    expect(snakeCase('Cartão de Crédito'), 'cartao_de_credito');
    expect(snakeCase('Configurações'), 'configuracoes');
    expect(pascalCase('Ícone'), 'Icone');
    expect(pascalCase('1. Flag'), 'C1Flag');
    expect(snakeCase('1. Flag'), 'c_1_flag');
    expect(pascalCase('🔥'), 'Component');
    expect(snakeCase('🔥'), 'component');
  });

  test('campo e valor de enum: camelCase, sem palavra reservada nem dígito no começo', () {
    expect(identifier('Mostrar ícone'), 'mostrarIcone');
    expect(identifier('default'), 'defaultValue');
    expect(identifier('2xl'), 'x2xl');
    expect(identifier('arrow-up-right'), 'arrowUpRight');
  });
}
