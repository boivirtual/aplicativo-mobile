/// Resolve o campo de peso quando o usuário digita uma fórmula estilo
/// Excel (ex: "=34+10,5"). Se o texto não começar com "=", devolve o texto
/// como veio, sem mexer. Se começar mas a expressão for inválida, lança
/// FormatException com uma mensagem pra mostrar ao usuário.
String resolverFormulaPeso(String texto) {
  final bruto = texto.trim();
  if (!bruto.startsWith('=')) return texto;

  final expressao = bruto.substring(1).trim();
  if (expressao.isEmpty) {
    throw const FormatException('Fórmula vazia.');
  }

  final resultado = _ParserExpressao(expressao).avaliar();
  return _formatarResultado(resultado);
}

String _formatarResultado(double valor) {
  if (valor.isNaN || valor.isInfinite) {
    throw const FormatException('Resultado inválido.');
  }
  final arredondado = double.parse(valor.toStringAsFixed(2));
  if (arredondado == arredondado.truncateToDouble()) {
    return arredondado.truncate().toString();
  }
  var texto = arredondado.toStringAsFixed(2);
  if (texto.endsWith('0')) texto = texto.substring(0, texto.length - 1);
  return texto;
}

/// Parser recursivo simples: expr := termo (('+'|'-') termo)*,
/// termo := fator (('*'|'/') fator)*, fator := '-' fator | '(' expr ')' | número.
/// Aceita "," ou "." como separador decimal (o campo de peso usa vírgula).
class _ParserExpressao {
  _ParserExpressao(String expressao)
      : _texto = expressao.replaceAll(',', '.').replaceAll(' ', '');

  final String _texto;
  int _pos = 0;

  double avaliar() {
    final valor = _expr();
    if (_pos != _texto.length) {
      throw FormatException(
        'Caractere inesperado em "${_texto.substring(_pos)}".',
      );
    }
    return valor;
  }

  double _expr() {
    var valor = _termo();
    while (_pos < _texto.length && (_atual() == '+' || _atual() == '-')) {
      final op = _atual();
      _pos++;
      final proximo = _termo();
      valor = op == '+' ? valor + proximo : valor - proximo;
    }
    return valor;
  }

  double _termo() {
    var valor = _fator();
    while (_pos < _texto.length && (_atual() == '*' || _atual() == '/')) {
      final op = _atual();
      _pos++;
      final proximo = _fator();
      if (op == '/') {
        if (proximo == 0) throw const FormatException('Divisão por zero.');
        valor = valor / proximo;
      } else {
        valor = valor * proximo;
      }
    }
    return valor;
  }

  double _fator() {
    if (_pos >= _texto.length) {
      throw const FormatException('Fórmula incompleta.');
    }
    if (_atual() == '-') {
      _pos++;
      return -_fator();
    }
    if (_atual() == '+') {
      _pos++;
      return _fator();
    }
    if (_atual() == '(') {
      _pos++;
      final valor = _expr();
      if (_pos >= _texto.length || _atual() != ')') {
        throw const FormatException('Parêntese não fechado.');
      }
      _pos++;
      return valor;
    }
    return _numero();
  }

  double _numero() {
    final inicio = _pos;
    while (_pos < _texto.length &&
        (_ehDigito(_texto[_pos]) || _texto[_pos] == '.')) {
      _pos++;
    }
    if (_pos == inicio) {
      throw FormatException(
        'Número esperado em "${_texto.substring(_pos)}".',
      );
    }
    final trecho = _texto.substring(inicio, _pos);
    final valor = double.tryParse(trecho);
    if (valor == null) {
      throw FormatException('Número inválido: "$trecho".');
    }
    return valor;
  }

  bool _ehDigito(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

  String _atual() => _texto[_pos];
}
