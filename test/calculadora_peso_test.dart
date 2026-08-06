import 'package:flutter_test/flutter_test.dart';
import 'package:boivirtual/utils/calculadora_peso.dart';

void main() {
  group('resolverFormulaPeso', () {
    test('texto sem "=" no início passa direto, sem mexer', () {
      expect(resolverFormulaPeso('34,5'), '34,5');
      expect(resolverFormulaPeso(''), '');
    });

    test('soma, subtração, multiplicação e divisão simples', () {
      expect(resolverFormulaPeso('=34+10'), '44');
      expect(resolverFormulaPeso('=34-10'), '24');
      expect(resolverFormulaPeso('=6*7'), '42');
      expect(resolverFormulaPeso('=20/8'), '2.5');
    });

    test('respeita precedência de operadores e parênteses', () {
      expect(resolverFormulaPeso('=2+3*4'), '14');
      expect(resolverFormulaPeso('=(2+3)*4'), '20');
      expect(resolverFormulaPeso('=100-20/2'), '90');
    });

    test('aceita vírgula como separador decimal (padrão do campo)', () {
      expect(resolverFormulaPeso('=34,5+10,25'), '44.75');
    });

    test('aceita número negativo e espaços dentro da fórmula', () {
      expect(resolverFormulaPeso('= -5 + 20 '), '15');
    });

    test('arredonda em 2 casas e remove zero à direita', () {
      expect(resolverFormulaPeso('=10/3'), '3.33');
      expect(resolverFormulaPeso('=4/2'), '2');
    });

    test('fórmula vazia lança FormatException', () {
      expect(() => resolverFormulaPeso('='), throwsFormatException);
    });

    test('expressão incompleta lança FormatException', () {
      expect(() => resolverFormulaPeso('=34+'), throwsFormatException);
    });

    test('caractere inesperado lança FormatException', () {
      expect(() => resolverFormulaPeso('=34+10x'), throwsFormatException);
    });

    test('divisão por zero lança FormatException', () {
      expect(() => resolverFormulaPeso('=10/0'), throwsFormatException);
    });

    test('parêntese não fechado lança FormatException', () {
      expect(() => resolverFormulaPeso('=(10+5'), throwsFormatException);
    });
  });
}
