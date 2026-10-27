// Os campos escondidos do web (cobertura, estação, tipo de gravação...) já
// são preenchidos ao escolher a fêmea e serão lidos na gravação (próxima
// etapa).
// ignore_for_file: unused_field

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/daos/animal_cache_dao.dart';
import '../data/daos/mapa_gado_dao.dart';
import '../services/animal_cache_service.dart';
import '../services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/mapa_gado_sync_service.dart';
import '../utils/app_alert.dart';
import '../widgets/campo_topo_widget.dart';
import '../widgets/indicador_conectividade_widget.dart';
import '../widgets/puxar_para_atualizar_widget.dart';
import '../widgets/seletor_campo_widget.dart';

/// Tela "Mapa de Gado - Nascimento" (modal #modal_nascimento do web, em
/// form_mapa_gados_movimentacao.php). No aplicativo é uma tela própria,
/// porque o formulário é extenso demais para um modal.
///
/// Só abre com o aplicativo online (ver _abrirNascimento em
/// PastoMovimentacaoWidget).
///
/// Campos (controle de estoque por animal), os mesmos que o web mostra em
/// cada opção:
///   - Nascimento: Data Nascimento, Nº Animal, Nº Mãe, Pai Nº, Monta,
///     Sexo, Raça, Pelagem e Peso;
///   - Aborto, Absorção e Natimorto: Data Ocorrência, Nº Fêmea e Sexo.
///
/// Já funcionam: os selects (Pai Nº, Raça e Pelagem, vindos do servidor) e
/// a digitação do Nº Mãe / Nº Fêmea, com a lista de aproximação (mesmos
/// critérios do web, ver AnimalCacheDao.buscarFemeasParaNascimento) — a
/// fêmea só vale depois de escolhida na lista, como o Nº Animal da Morte.
/// Ao escolher a fêmea a tela consulta o servidor e aplica as mesmas
/// regras de ler_animal_mae() do web (estação de monta, pai, raça e os
/// avisos de diagnóstico, aborto/natimorto, gemelar e 9 meses) — ver
/// [_NascimentoPastoScreenState._aplicarMae]. O Confirmar grava pelos próprios
/// scripts do web no servidor (ver [_NascimentoPastoScreenState._confirmar]).
class NascimentoPastoScreen extends StatefulWidget {
  final String bd;
  final int fazendaId;
  final String fazendaCodigo;
  final String nomeFazenda;
  final int pastoId;
  final String nomePasto;
  final String? usuario;

  const NascimentoPastoScreen({
    super.key,
    required this.bd,
    required this.fazendaId,
    required this.fazendaCodigo,
    required this.nomeFazenda,
    required this.pastoId,
    required this.nomePasto,
    required this.usuario,
  });

  @override
  State<NascimentoPastoScreen> createState() => _NascimentoPastoScreenState();
}

/// Uma opção do "Pai Nº" (o web separa em dois grupos: SEMEM e ANIMAIS).
class _OpcaoPai {
  final String id;
  final String texto;
  final String grupo;
  const _OpcaoPai(this.id, this.texto, this.grupo);
}

class _NascimentoPastoScreenState extends State<NascimentoPastoScreen> {
  static const _azul = Color(0xFF18385F);
  static const _verde = Color(0xFF4CAF50);
  static const _azulVoltar = Color(0xFF4BBAEB);
  static final _corRotulo = Colors.blueGrey[800]!;

  /// Mesmos valores do web (radio opcao_nascimento): N = Nascimento,
  /// A = Aborto, B = Absorção, M = Natimorto.
  static const _opcoes = [
    MapEntry('N', 'Nascimento'),
    MapEntry('A', 'Aborto'),
    MapEntry('B', 'Absorção'),
    MapEntry('M', 'Natimorto'),
  ];

  final _maeController = TextEditingController();
  final _maeFoco = FocusNode();
  final _animalController = TextEditingController();
  final _pesoController = TextEditingController();

  String? _opcao;
  DateTime _data = _hoje();
  String? _sexo; // 'M' ou 'F'
  _OpcaoPai? _pai;
  String? _raca;
  String? _pelagem;

  // Selects (vêm do servidor ao abrir a tela).
  List<_OpcaoPai> _pais = [];
  List<MapEntry<String, String>> _racas = [];
  List<MapEntry<String, String>> _pelagens = [];
  bool _carregandoListas = true;
  bool _falhaListas = false;

  // Nº Mãe / Nº Fêmea
  bool _temCadastro = true;
  bool _atualizandoCadastro = false;
  List<Map<String, dynamic>> _sugestoes = [];
  Map<String, dynamic>? _mae; // linha de animais_cache escolhida na lista
  bool _maeInvalida = false;
  int _buscaAtual = 0;
  Timer? _esperaNaoEncontrado;
  OverlayEntry? _avisoNaoEncontrado;
  bool _consultandoMae = false;

  // Parâmetros de nascimento da fazenda (ler_parametro_nascimento.php).
  final _alfaController = TextEditingController();
  bool _mostraAlfa = false;
  String _grupoUsuario = '';

  // Linha "Estação de Monta: 25/2026" / "Monta:" / "Monta Natural" e o
  // aviso vermelho ao lado (.desc_novo_nascimento).
  String _rotuloMonta = 'Estação de Monta:';
  String _estacao = '';
  String _descNovoNascimento = '';

  // Campos escondidos do web, preenchidos ao escolher a fêmea (usados na
  // gravação — próxima etapa).
  String _maeId = '';
  String _coberturaId = '';
  String _itemCobertura = '';
  String _dataInseminacao = '';
  String _diasNascimento = '';
  String _estacaoId = '';
  int _tipoGravacao = 0;
  String _tipoCobertura = '';
  String _dataPrenhes = '';

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime _hoje() {
    final a = DateTime.now();
    return DateTime(a.year, a.month, a.day);
  }

  static String _formatar(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// "C-000000087" -> "C-87"; "000001874" -> "1874" (como a Pesagem mostra).
  static String _exibicao(String codigo) {
    if (codigo.contains('-')) {
      final partes = codigo.split('-');
      final numero = partes[1].replaceFirst(RegExp(r'^0+'), '');
      return '${partes[0]}-${numero.isEmpty ? '0' : numero}';
    }
    final numero = codigo.replaceFirst(RegExp(r'^0+'), '');
    return numero.isEmpty ? '0' : numero;
  }

  @override
  void initState() {
    super.initState();
    _carregarListas();
    _carregarCadastro();
    _carregarParametros();
    _carregarRegistrosHoje();
  }

  @override
  void dispose() {
    _esperaNaoEncontrado?.cancel();
    _avisoNaoEncontrado?.remove();
    _maeController.dispose();
    _alfaController.dispose();
    _maeFoco.dispose();
    _animalController.dispose();
    _pesoController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Dados
  // ---------------------------------------------------------------------

  /// Pai Nº, Raça e Pelagem — mesmas listas do web.
  Future<void> _carregarListas() async {
    setState(() {
      _carregandoListas = true;
      _falhaListas = false;
    });
    final dados = await MapaGadoSyncService.instance.buscarListasNascimento(
      widget.bd,
    );
    if (!mounted) return;
    if (dados == null) {
      setState(() {
        _carregandoListas = false;
        _falhaListas = true;
      });
      return;
    }
    List<Map> lista(String chave) =>
        ((dados[chave] as List?) ?? const []).cast<Map>();
    String txt(Map m, String c) => (m[c] ?? '').toString().trim();

    final pais = <_OpcaoPai>[
      for (final s in lista('semens'))
        _OpcaoPai(
          txt(s, 'id'),
          '${txt(s, 'nome')} - ${txt(s, 'raca')}',
          'SEMEM',
        ),
      for (final a in lista('machos'))
        _OpcaoPai(
          txt(a, 'id'),
          '${_exibicao(txt(a, 'alfa').isEmpty ? txt(a, 'numerico') : '${txt(a, 'alfa')}-${txt(a, 'numerico')}')}'
              ' - ${txt(a, 'raca')}',
          'ANIMAIS',
        ),
    ];
    setState(() {
      _pais = pais;
      _racas = [
        for (final r in lista('racas'))
          MapEntry(txt(r, 'id'), txt(r, 'descricao')),
      ];
      _pelagens = [
        for (final p in lista('pelagens'))
          MapEntry(txt(p, 'id'), txt(p, 'descricao')),
      ];
      _carregandoListas = false;
    });
  }

  /// Código alfa e próximo número do animal, a estação de monta da
  /// fazenda e o grupo do usuário — como o web faz ao abrir a tela.
  Future<void> _carregarParametros() async {
    final prefs = await SharedPreferences.getInstance();
    final dados = await MapaGadoSyncService.instance.consultarNascimento({
      'acao': 'parametros',
      'bd': widget.bd,
      'fazenda': widget.fazendaId,
      'usuario_id': int.tryParse(prefs.getString('userId') ?? '') ?? 0,
    });
    if (!mounted || dados == null) return;
    final alfa = (dados['codigo_alfa'] ?? '').toString();
    final numero = (dados['codigo_numerico'] ?? '').toString();
    setState(() {
      _grupoUsuario = (dados['grupo_usuario'] ?? '').toString();
      _mostraAlfa = alfa.isNotEmpty;
      _alfaController.text = alfa;
      _animalController.text = numero;
      if (numero.isNotEmpty) {
        _estacao = (dados['estacao'] ?? '').toString();
        _estacaoId = (dados['estacao_id'] ?? '').toString();
      }
    });
  }

  /// Como na Morte: busca o cadastro de animais do servidor ao abrir, para
  /// a lista do Nº Mãe refletir o que foi feito na web (animal baixado,
  /// reativado, cadastrado...). A busca já funciona com o que está no
  /// aparelho enquanto o download roda.
  Future<void> _carregarCadastro() async {
    final tem = await AnimalCacheDao.instance.temCacheParaFazenda(
      widget.fazendaCodigo,
    );
    if (!mounted) return;
    setState(() => _temCadastro = tem);
    if (!ConnectivityService.instance.temInternetReal) return;
    setState(() => _atualizandoCadastro = true);
    await AnimalCacheService.instance.garantirCacheCompleto(
      widget.bd,
      forcar: true,
    );
    if (!mounted) return;
    final temAgora = await AnimalCacheDao.instance.temCacheParaFazenda(
      widget.fazendaCodigo,
    );
    if (!mounted) return;
    setState(() {
      _atualizandoCadastro = false;
      _temCadastro = temAgora;
    });
    // Refaz a busca em andamento com o cadastro novo.
    if (_mae == null && _maeController.text.trim().isNotEmpty) {
      _aoDigitarMae(_maeController.text);
    }
  }

  // ---------------------------------------------------------------------
  // Nº Mãe / Nº Fêmea — lista de aproximação (igual ao Nº Animal da Morte)
  // ---------------------------------------------------------------------

  Future<void> _aoDigitarMae(String termo) async {
    final busca = ++_buscaAtual;
    _esperaNaoEncontrado?.cancel();
    // Mexeu no número: a fêmea precisa ser escolhida de novo.
    setState(() {
      _mae = null;
      _maeInvalida = false;
    });
    if (termo.trim().isEmpty) {
      setState(() => _sugestoes = []);
      return;
    }
    final lista = await AnimalCacheDao.instance.buscarFemeasParaNascimento(
      widget.fazendaCodigo,
      termo,
    );
    if (!mounted || busca != _buscaAtual) return;
    setState(() => _sugestoes = lista);
    if (lista.isEmpty) {
      _esperaNaoEncontrado = Timer(const Duration(milliseconds: 800), () {
        if (!mounted || busca != _buscaAtual) return;
        // Cadastro ainda baixando: a busca é refeita quando terminar.
        if (_atualizandoCadastro) return;
        _maeController.clear();
        _mostrarNaoEncontrado(
          'Cód ${termo.trim()} não encontrado ou está inativo!',
        );
      });
    }
  }

  // ---------------------------------------------------------------------
  // Fêmea escolhida — ler_animal_mae() do web (js/mapa_gados.js)
  // ---------------------------------------------------------------------

  /// Toque na lista de aproximação: consulta a fêmea no servidor
  /// (ler_animal_femea_nascimento.php) e aplica as mesmas regras do web.
  Future<void> _escolherMae(Map<String, dynamic> animal) async {
    final busca = ++_buscaAtual;
    _esperaNaoEncontrado?.cancel();
    final codigo = animal['codigo']?.toString() ?? '';
    setState(() {
      _mae = null;
      _maeInvalida = false;
      _sugestoes = [];
      _maeController.text = _exibicao(codigo);
      _consultandoMae = true;
    });
    _maeFoco.unfocus();

    final dados = await MapaGadoSyncService.instance.consultarNascimento({
      'acao': 'mae',
      'bd': widget.bd,
      'fazenda': widget.fazendaId,
      'codigo': codigo,
      'data': _iso(_data),
    });
    if (!mounted || busca != _buscaAtual) return;
    setState(() => _consultandoMae = false);

    if (dados == null) {
      _limparMae();
      await AppAlert.erro(
        context,
        'Não foi possível consultar a fêmea no servidor. Verifique a '
        'internet e tente novamente.',
      );
      return;
    }
    if (dados['encontrado'] != true) {
      // web: o campo fica com "Não encontrado"
      _limparMae();
      _mostrarNaoEncontrado(
        'Cód ${_exibicao(codigo)} não encontrado ou está inativo!',
      );
      return;
    }
    final php = [
      for (final v in (dados['php'] as List? ?? const [])) v?.toString() ?? '',
    ];
    while (php.length < 24) {
      php.add('');
    }
    await _aplicarMae(animal, php);
  }

  /// Número como o JavaScript do web compara ('' vale 0).
  static double _num(String v) =>
      v.trim().isEmpty ? 0 : (double.tryParse(v.trim()) ?? double.nan);

  /// Grupos 01 e 03 (administradores) decidem nos avisos; os outros só
  /// recebem "Entre em contato com o Administrador do Sistema".
  bool get _administrador {
    final g = _num(_grupoUsuario);
    return g == 1 || g == 3;
  }

  void _limparMae() {
    setState(() {
      _mae = null;
      _maeController.clear();
      _sugestoes = [];
    });
  }

  Future<void> _aplicarMae(
    Map<String, dynamic> animal,
    List<String> php,
  ) async {
    final exib = _exibicao(animal['codigo']?.toString() ?? '');
    final estacao = php[12];

    // $("#codigo_mae_consulta").val(id + ' - ' + raça) e o id da fêmea
    void marcarMae() {
      _mae = animal;
      _maeId = php[0];
      _maeController.text = '$exib - ${php[2]}';
    }

    // campos que o web preenche com o que veio da cobertura
    void dadosDaCobertura() {
      _definirPai(php[3]);
      _definirRaca(php[11]);
      _coberturaId = php[4];
      _itemCobertura = php[5];
      _dataInseminacao = php[6];
      _diasNascimento = php[7];
      _estacaoId = php[8];
      _estacao = estacao;
      _tipoGravacao = 0;
      _tipoCobertura = php[15];
      _dataPrenhes = php[16];
    }

    // "Limpa dados da estação para Monta"
    void limparParaMonta() {
      _pai = null;
      _raca = null;
      _coberturaId = '0';
      _itemCobertura = '';
      _estacaoId = '';
      _estacao = '';
      _tipoGravacao = 0;
      _tipoCobertura = 'M';
      _rotuloMonta = 'Monta:';
      _dataPrenhes = '';
    }

    final diag = php[1];
    final controle = php[15];

    if (diag == 'N') {
      setState(() {
        marcarMae();
        _estacaoId = php[8];
        _estacao = estacao;
        _rotuloMonta = 'Estação de Monta:';
      });
      if (php[8] == php[14] && controle == 'C') {
        // negativo na estação atual
        await _modalEstacao(
          'Diagnóstico negativo estação $estacao',
          linhas: const [
            '-Clique em Substituir por Monta Natural OU;',
            '-Clique em ALTERAR DIAGNÓSTICO OU;',
            '-Selecione outra fêmea.',
          ],
          botoes: const ['substituir', 'alterar', 'outra'],
        );
        return;
      } else if (controle == 'C') {
        // negativo na estação anterior e não entrou na estação atual
        if (_num(php[22]) < 9) {
          await _modalEstacao(
            'Esta Fêmea não está em estação de monta. Diagnóstico negativo '
            'estação $estacao',
            linhas: const [
              '-Clique em Substituir por Monta Natural OU;',
              '-Clique em ALTERAR DIAGNÓSTICO OU;',
              '-Selecione outra fêmea.',
            ],
            botoes: const ['alterar', 'substituir', 'outra'],
          );
          return;
        }
        // diagnóstico negativo há 9 meses ou mais: Monta Natural
        setState(limparParaMonta);
        return;
      }
    } else if (diag == 'D' && controle == 'C') {
      _limparMae();
      await AppAlert.erro(context, 'Estação: $estacao Aguardando Diagnóstico.');
      return;
    } else if (diag == 'I' && controle == 'C') {
      _limparMae();
      await AppAlert.erro(context, 'Estação: $estacao Aguardando Inseminação.');
      return;
    } else if (diag == 'P') {
      setState(() {
        marcarMae();
        dadosDaCobertura();
        _rotuloMonta = 'Estação de Monta:';
        if (_num(php[4]) != 0 && php[20] == 'A') {
          _coberturaId = '0';
          _itemCobertura = '';
        }
      });
    }

    if (_opcao == 'N') {
      if (_num(php[4]) == 0 || controle == 'M') {
        setState(() {
          marcarMae();
          dadosDaCobertura();
          _rotuloMonta = 'Monta:';
          _estacao = '';
          if (php[20] == 'A') {
            _coberturaId = '0';
            _itemCobertura = '';
          }
        });
      }
      if (_num(php[10]) == 1 && _num(php[18]) <= 90) {
        await _avisoAbortoNatimorto(
          'Essa fêmea teve aborto ou natimorto nos últimos 90 dias',
        );
        return;
      }
      if (_num(php[10]) == 1 && _num(php[21]) < 9) {
        await _avisoAbortoNatimorto(
          'Essa fêmea teve aborto ou natimorto nos últimos 9 meses',
        );
        return;
      }
      if (_num(php[9]) != 0) {
        final mesmaData = _iso(_data) == php[13];
        if (controle == 'C') {
          if (mesmaData) {
            await _avisoGemelar(
              'Fêmea já possui nascimento na estação $estacao',
            );
            return;
          }
          if (_num(php[17]) < 9) {
            await _modalEstacao(
              'Esta fêmea teve nascimento na estação  $estacao',
              linhas: const [
                '-Para GEMELAR, VOLTAR e informar a mesma data de nascimento OU;',
                '-Clique em Substituir por Monta Natural OU;',
                '-Selecione outra fêmea.',
              ],
              botoes: const ['substituir', 'outra'],
            );
            return;
          }
          setState(limparParaMonta);
          return;
        } else if (controle == 'M') {
          if (mesmaData) {
            await _avisoGemelar('Fêmea já possui nascimento nessa data.');
            return;
          }
          if (_num(php[10]) == 1 && _num(php[18]) <= 90) {
            await _avisoAbortoNatimorto(
              'Essa fêmea teve aborto ou natimorto nos últimos 90 dias',
            );
            return;
          }
          if (_num(php[17]) < 9) {
            await _modalEstacao(
              'Essa fêmea possui bezerro nascido há menos de 9 meses.',
              linhas: const [
                '-Para GEMELAR, VOLTAR e informar a mesma data de nascimento OU;',
                '-Selecione outra fêmea.;',
              ],
              botoes: const ['outra', 'voltar'],
            );
            return;
          }
        }
      }
    } else {
      // Aborto, Absorção e Natimorto
      if (_num(php[10]) == 1) {
        if (controle == 'C' && _num(php[18]) <= 90) {
          await _avisoAbortoNatimorto(
            'Essa fêmea teve aborto ou natimorto na estação $estacao nos '
            'últimos 90 dias',
          );
          return;
        } else if (controle == 'M' && _num(php[18]) <= 90) {
          await _avisoAbortoNatimorto(
            'Essa fêmea teve aborto ou natimorto nos últimos 90 dias',
          );
          return;
        }
      }
      if (_num(php[9]) != 0 && php[19] != '') {
        if (controle == 'C' && _num(php[19]) <= 90) {
          await _avisoAbortoNatimorto(
            'Essa fêmea teve nascimento na estação $estacao nos últimos 90 '
            'dias',
          );
          return;
        } else if (controle == 'M' && _num(php[19]) <= 90) {
          await _avisoAbortoNatimorto(
            'Essa fêmea teve nascimento nos últimos 90 dias',
          );
          return;
        }
      }
      setState(() {
        marcarMae();
        _tipoGravacao = 0;
        _tipoCobertura = 'M';
        if (_num(php[10]) == 1 && _num(php[18]) > 90) {
          // último aborto/natimorto há mais de 90 dias: outro por MONTA
          _coberturaId = '0';
          _itemCobertura = '';
          _estacaoId = '';
          _dataPrenhes = '';
        } else {
          _coberturaId = php[4];
          _itemCobertura = php[5];
          _estacaoId = php[8];
          _dataPrenhes = php[16];
        }
        if (_num(php[4]) != 0 && php[20] == 'N') {
          _coberturaId = '0';
          _itemCobertura = '';
        }
      });
    }
  }

  /// $("#codigo_pai_animal").val(id): '000000000' (ou um id que não está
  /// na lista) deixa o select em "...".
  void _definirPai(String id) {
    _pai = null;
    for (final o in _pais) {
      if (o.id == id) {
        _pai = o;
        break;
      }
    }
  }

  void _definirRaca(String id) {
    _raca = _racas.any((r) => r.key == id) ? id : null;
  }

  /// volta_nascimento_mensagem() do web.
  void _voltaNascimentoMensagem() {
    setState(() {
      _mae = null;
      _maeId = '';
      _maeController.clear();
      _pai = null;
      _coberturaId = '';
      _itemCobertura = '';
      _tipoGravacao = 0;
    });
  }

  /// selecinarOutraFemea() / fecharModalEstacao() / voltarModalEstacao().
  void _outraFemea({bool marcarCampo = true}) {
    setState(() {
      _mae = null;
      _maeId = '';
      _maeController.clear();
      _pai = null;
      _maeInvalida = marcarCampo;
      _descNovoNascimento = '';
    });
  }

  /// #nascimento_aborto_natimorto: "ATENÇÃO!" + mensagem, botão Fechar.
  Future<void> _avisoAbortoNatimorto(String mensagem) async {
    await _mensagem(
      linhas: [mensagem],
      atencao: true,
      botoes: [_BotaoAviso('Fechar', Colors.grey.shade600, 'fechar')],
    );
    if (mounted) _voltaNascimentoMensagem();
  }

  /// #nascimento_gemelar.
  Future<void> _avisoGemelar(String mensagem) async {
    final r = await _mensagem(
      linhas: [mensagem],
      botoes: const [
        _BotaoAviso('Voltar e conferir a Fêmea', _verde, 'voltar'),
        _BotaoAviso('Nascimento Gemelar', Color(0xFFD9534F), 'gemelar'),
      ],
    );
    if (!mounted) return;
    if (r == 'gemelar') {
      setState(() => _descNovoNascimento = 'Nascimento Gemelar.');
    } else {
      _voltaNascimentoMensagem();
    }
  }

  /// #modal_estacao. Para quem não é administrador (grupos 01 e 03) o web
  /// troca as instruções por "Entre em contato com o Administrador do
  /// Sistema" e deixa só o Fechar.
  Future<void> _modalEstacao(
    String descricao, {
    required List<String> linhas,
    required List<String> botoes,
  }) async {
    const rotulos = {
      'substituir': _BotaoAviso(
        'Substituir por Monta Natural',
        Color(0xFF007AFF),
        'substituir',
      ),
      'alterar': _BotaoAviso(
        'Alterar Diagnóstico',
        Color(0xFF78909C),
        'alterar',
      ),
      'outra': _BotaoAviso('Selecione Outra Fêmea', Color(0xFFD9534F), 'outra'),
      'voltar': _BotaoAviso('Voltar', Color(0xFF78909C), 'voltar'),
    };
    final adm = _administrador;
    final r = await _mensagem(
      atencao: true,
      destaque: descricao,
      administrador: !adm,
      linhas: adm ? linhas : const [],
      botoes: adm
          ? [for (final b in botoes) rotulos[b]!]
          : const [_BotaoAviso('Fechar', Color(0xFF78909C), 'fechar')],
    );
    if (!mounted) return;
    switch (r) {
      case 'substituir':
        await _substituirPorMontaNatural();
      case 'alterar':
        // No web este botão abre a tela de diagnóstico da cobertura, que o
        // aplicativo não tem.
        _outraFemea();
        await AppAlert.erro(
          context,
          'A alteração do diagnóstico é feita no sistema web (Reprodução > '
          'Cobertura > Diagnóstico). Depois de alterar, informe a fêmea '
          'novamente.',
        );
      case 'voltar':
        _outraFemea(marcarCampo: false);
      default:
        _outraFemea();
    }
  }

  /// substituir_por_monta_natural() do web.
  Future<void> _substituirPorMontaNatural() async {
    void aplicar(int tipoGravacao) {
      setState(() {
        _tipoGravacao = tipoGravacao;
        _rotuloMonta = 'Monta Natural';
        _estacao = '';
        _coberturaId = '0';
        _tipoCobertura = 'M';
        _dataPrenhes = '';
        _pai = null;
      });
    }

    if (_opcao != 'N') {
      aplicar(0);
      return;
    }
    final dados = await MapaGadoSyncService.instance.consultarNascimento({
      'acao': 'ultimo_nascimento',
      'bd': widget.bd,
      'mae': _maeId,
      'data': _iso(_data),
    });
    if (!mounted) return;
    if (dados == null) {
      await _mensagem(
        atencao: true,
        linhas: const ['Erro não previsto: sem resposta do servidor'],
        botoes: const [_BotaoAviso('Fechar', Color(0xFF78909C), 'fechar')],
      );
      return;
    }
    final meses = double.tryParse(dados['meses']?.toString() ?? '') ?? 999;
    if (meses < 9) {
      await _mensagem(
        atencao: true,
        linhas: const [
          'Essa fêmea possui bezerro nascido há menos de 9 meses.',
        ],
        botoes: const [_BotaoAviso('Fechar', Color(0xFF78909C), 'fechar')],
      );
      if (!mounted) return;
      // fechar_nascimento_nove_meses()
      setState(() {
        _sexo = null;
        _mae = null;
        _maeId = '';
        _maeController.clear();
        _pai = null;
        _raca = null;
        _pelagem = null;
        _pesoController.clear();
        _tipoGravacao = 0;
        _maeInvalida = true;
      });
      return;
    }
    aplicar(3);
  }

  /// Modal "Nascimento - Mensagem" (padrão dos modais do aplicativo).
  /// Devolve a ação do botão tocado.
  Future<String?> _mensagem({
    required List<String> linhas,
    required List<_BotaoAviso> botoes,
    bool atencao = false,
    String? destaque,
    bool administrador = false,
    bool linhasVermelhas = false,
  }) {
    FocusManager.instance.primaryFocus?.unfocus();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Nascimento - Mensagem',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, color: _azul),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (atencao) ...[
                          const Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Color(0xFFF0AD4E),
                                size: 22,
                              ),
                              SizedBox(width: 6),
                              Text('ATENÇÃO!', style: TextStyle(fontSize: 14)),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (destaque != null) ...[
                          Text(
                            destaque,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(offset: Offset(0.4, 0)),
                                Shadow(offset: Offset(-0.4, 0)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (administrador)
                          const Text(
                            'Entre em contato com o Administrador do Sistema',
                            style: TextStyle(fontSize: 14, color: Colors.red),
                          ),
                        for (final l in linhas)
                          Padding(
                            padding: EdgeInsets.only(
                              left: destaque == null || linhasVermelhas
                                  ? 0
                                  : 12,
                              bottom: 4,
                            ),
                            child: Text(
                              l,
                              style: TextStyle(
                                fontSize: 14,
                                color: linhasVermelhas ? Colors.red : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (final b in botoes) ...[
                    const SizedBox(height: 8),
                    _botao(b.texto, b.cor, () => Navigator.pop(ctx, b.acao)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// No web, tocar no campo já preenchido limpa a fêmea para digitar outra
  /// (e some o aviso vermelho ao lado da estação).
  void _aoTocarMae() {
    if (_maeInvalida) setState(() => _maeInvalida = false);
    if (_mae == null && _maeController.text.isEmpty) return;
    if (_mae == null) return;
    setState(() {
      _mae = null;
      _maeId = '';
      _maeController.clear();
      _sugestoes = [];
      _descNovoNascimento = '';
    });
  }

  /// Aviso vermelho no padrão da Pesagem/Morte: fica na tela até tocar em
  /// FECHAR e devolve o foco ao campo.
  void _mostrarNaoEncontrado(String mensagem) {
    _fecharNaoEncontrado(focar: false);
    FocusManager.instance.primaryFocus?.unfocus();
    _avisoNaoEncontrado = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).size.height * 0.35,
        left: 30,
        right: 30,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 25, 10, 10),
            decoration: BoxDecoration(
              color: Colors.red[900]!.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Text(
                        mensagem,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Align(
                  alignment: Alignment.bottomRight,
                  child: TextButton(
                    onPressed: _fecharNaoEncontrado,
                    child: const Text(
                      'FECHAR',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_avisoNaoEncontrado!);
  }

  void _fecharNaoEncontrado({bool focar = true}) {
    _avisoNaoEncontrado?.remove();
    _avisoNaoEncontrado = null;
    if (focar && mounted) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && _maeFoco.canRequestFocus) _maeFoco.requestFocus();
      });
    }
  }

  // ---------------------------------------------------------------------
  // Ações
  // ---------------------------------------------------------------------

  /// Como no web: trocar de opção limpa os campos.
  void _escolherOpcao(String valor) {
    if (_opcao == valor) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _buscaAtual++;
    _esperaNaoEncontrado?.cancel();
    _marcarMae();
    setState(() {
      _opcao = valor;
      _data = _hoje();
      _sexo = null;
      _pai = null;
      _raca = null;
      _pelagem = null;
      _mae = null;
      _maeInvalida = false;
      _sugestoes = [];
      _maeController.clear();
      _pesoController.clear();
      // como no web: zera o que veio da fêmea anterior; o código alfa, o
      // número do animal e a estação continuam como estavam
      _maeId = '';
      _consultandoMae = false;
      _descNovoNascimento = '';
      _coberturaId = '';
      _itemCobertura = '';
      _dataInseminacao = '';
      _diasNascimento = '';
      _tipoGravacao = 0;
    });
  }

  Future<void> _escolherData() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2000),
      lastDate: _hoje(),
      helpText: _opcao == 'N' ? 'Data do nascimento' : 'Data da ocorrência',
    );
    if (d == null) return;
    // como no web: trocar a data limpa a fêmea e o pai
    _buscaAtual++;
    setState(() {
      _data = d;
      _mae = null;
      _maeId = '';
      _maeController.clear();
      _sugestoes = [];
      _pai = null;
      _consultandoMae = false;
    });
  }

  /// "Pai Nº": são milhares de opções (todo sêmen e todo macho), então em
  /// vez do menu simples abre uma lista com busca, nos mesmos dois grupos
  /// do web (SEMEM e ANIMAIS).
  Future<void> _escolherPai() async {
    if (_pais.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final escolhido = await showDialog<_OpcaoPai>(
      context: context,
      builder: (_) => _ListaPaiDialog(
        opcoes: _pais,
        selecionado: _pai?.id,
        corRotulo: _corRotulo,
        corTitulo: _azul,
        corFechar: _azulVoltar,
      ),
    );
    if (escolhido == null || !mounted) return;
    // a primeira linha ("...") limpa o pai, como no web
    setState(() => _pai = escolhido.id.isEmpty ? null : escolhido);
  }

  // ---------------------------------------------------------------------
  // Confirmar — confirmar_nascimento() do web (js/mapa_gados.js). A
  // gravação é feita pelos próprios scripts do web no servidor
  // (gravar_nascimento.php / gravar_nascimento_aborto_natimorto.php).
  // ---------------------------------------------------------------------

  bool _gravando = false;

  Future<void> _confirmar() async {
    if (_gravando) return;
    FocusManager.instance.primaryFocus?.unfocus();

    // O Nascimento só funciona online (a internet pode ter caído com a
    // tela aberta).
    final nivel = await ConnectivityService.instance.verificarAgora();
    if (!mounted) return;
    if (nivel != NivelConexao.internetOk) {
      await AppAlert.erro(
        context,
        'Sem internet ou internet ruim!\n\nO Nascimento só pode ser '
        'confirmado com o aplicativo online. Tente novamente quando a '
        'internet estiver estável.',
      );
      return;
    }

    if (_opcao != 'N') {
      await _gravar('gravar_aborto_natimorto');
      return;
    }
    // sem cobertura (ou monta natural sem data da prenhes): monta natural
    if ((_tipoCobertura == 'M' && _dataPrenhes == '') ||
        _num(_coberturaId) == 0) {
      await _gravarMontaNatural();
      return;
    }
    final dias = _num(_diasNascimento);
    if (dias >= 252 && dias <= 303) {
      await _gravarNascimento();
    } else {
      await _avisoDiasGestacao();
    }
  }

  /// gravar_nascimento() do web (tipo_gravacao 0).
  Future<void> _gravarNascimento() async {
    if (_tipoCobertura == 'M') {
      await _gravarMontaNatural();
      return;
    }
    await _gravar('gravar_nascimento');
  }

  /// gravar_nascimento_monta_natural() do web (tipo_gravacao 3).
  Future<void> _gravarMontaNatural() async {
    setState(() => _tipoGravacao = 3);
    await _gravar('gravar_nascimento');
  }

  /// #nascimento_erro do web: gestação fora de 252 a 303 dias.
  Future<void> _avisoDiasGestacao() async {
    final estacao = _tipoCobertura == 'C' ? 'Estação $_estacao: ' : '';
    final controleI = await MapaGadoDao.instance.controleEstoque(widget.bd);
    if (!mounted) return;
    final porAnimal = controleI == 'I';
    final adm = _administrador;

    final linhas = <String>[];
    final botoes = <_BotaoAviso>[];
    if (adm && porAnimal) {
      botoes.add(const _BotaoAviso('Confirmar Nascimento', _verde, 'gravar'));
      if (_tipoCobertura == 'C') {
        botoes.add(
          const _BotaoAviso(
            'Substituir por Monta Natural',
            Color(0xFF007AFF),
            'substituir',
          ),
        );
      } else {
        linhas.add(
          'Atenção! Ao confirmar o nascimento você estará alterando a data '
          'da prenhes.',
        );
      }
    } else if (porAnimal) {
      linhas.add('Entre em contato com o Administrador do Sistema');
    } else {
      botoes.add(const _BotaoAviso('Confirmar Nascimento', _verde, 'gravar'));
      botoes.add(
        const _BotaoAviso(
          'Substituir por Monta Natural',
          Color(0xFF007AFF),
          'substituir',
        ),
      );
    }
    botoes.add(const _BotaoAviso('Não Confirmar', Color(0xFFD9534F), 'nao'));

    final r = await _mensagem(
      destaque:
          '${estacao}Animal com ( ${_diasNascimento.trim()} dias ) de '
          'gestação. Previsão (~ 282 dias)',
      linhasVermelhas: true,
      linhas: linhas,
      botoes: botoes,
    );
    if (!mounted) return;
    switch (r) {
      case 'gravar':
        await _gravarNascimento();
      case 'substituir':
        setState(() => _pai = null);
        await _gravarMontaNatural();
      default:
        // fechar_nascimento_erro()
        setState(() {
          _sexo = null;
          _mae = null;
          _maeId = '';
          _maeController.clear();
          _pai = null;
          _raca = null;
          _pelagem = null;
          _pesoController.clear();
          _tipoGravacao = 0;
        });
    }
  }

  /// Os campos do formulário #form_gravar_animal do web, com os mesmos
  /// nomes e valores ($('#form_gravar_animal').serialize()).
  Map<String, String?> get _camposFormulario => {
    'grupo_usuario': _grupoUsuario,
    'tipo_gravacao': '$_tipoGravacao',
    'num_mov_nascimento': '0',
    'codigo_mae_animal': _maeId,
    'dias_nascimento': _diasNascimento,
    'cobertura_id': _coberturaId,
    'item_cobertura': _itemCobertura,
    'tipo_cobertura': _tipoCobertura,
    'data_prenhes': _dataPrenhes,
    'estacao_monta_id': _estacaoId,
    'data_inseminacao': _dataInseminacao,
    'local_id': '${widget.fazendaId}',
    'pasto_id': '${widget.pastoId}',
    'opcao_nascimento': _opcao,
    'nascimento_animal': _iso(_data),
    'codigo_mae_consulta': _maeController.text,
    'codigo_pai_animal': _pai?.id ?? '000000000',
    'alfa_animal': _mostraAlfa ? _alfaController.text : '',
    'codigo_animal_id': '',
    'codigo_numerico_animal': _animalController.text,
    'qtd_animal': '',
    // sem escolher, o web não envia o sexo
    'sexo_animal': _sexo,
    'raca_id': _raca ?? '',
    'pelagem_id': _pelagem ?? '',
    'peso_animal': _pesoController.text,
  };

  /// Envia ao servidor e trata a resposta como o web.
  Future<void> _gravar(String acao) async {
    final nascimento = acao == 'gravar_nascimento';
    setState(() => _gravando = true);
    final resposta = await MapaGadoSyncService.instance.gravarNascimento(
      acao: acao,
      bd: widget.bd,
      usuario: widget.usuario ?? '',
      campos: _camposFormulario,
    );
    if (!mounted) return;
    setState(() => _gravando = false);

    if (resposta == null) {
      if (nascimento) setState(() => _tipoGravacao = 0);
      await AppAlert.erro(
        context,
        'Não foi possível confirmar: sem resposta do servidor. Verifique a '
        'internet e tente novamente.',
      );
      return;
    }
    final mensagem = (resposta['message'] ?? '').toString();
    if (resposta['success'] != true) {
      if (nascimento) setState(() => _tipoGravacao = 0);
      await AppAlert.erro(context, mensagem);
      if (!mounted) return;
      // fechar_erro_gravar(): sem a fêmea validada, limpa o campo e o pai
      if (_maeId.isEmpty || _num(_maeId) == 0) {
        setState(() {
          _mae = null;
          _maeController.clear();
          _pai = null;
          _maeInvalida = true;
        });
      }
      return;
    }

    // Gravou: o mapa e o cadastro de animais mudaram no servidor.
    MapaGadoSyncService.instance.atualizarDepoisDoNascimento(
      widget.bd,
      widget.fazendaId,
    );

    final descricaoLote = (resposta['descricao_lote'] ?? '').toString();
    if (nascimento && descricaoLote.isEmpty) {
      // Pasto sem Descrição do Lote: o web abre a Composição da Descrição
      // do Lote — aqui volta para o pasto e ela abre lá.
      await AppAlert.sucesso(
        context,
        '$mensagem\nNecessário incluir a Descrição do Lote para o Pasto: '
        '${resposta['descricao_pasto'] ?? widget.nomePasto}',
      );
      if (mounted) Navigator.pop(context, 'descricao_lote');
      return;
    }
    await AppAlert.sucesso(context, mensagem);
    if (!mounted) return;
    // ler_animal_nascimento(): tela limpa para o próximo, com o próximo
    // número do animal.
    // a opção (Nascimento, Aborto...) continua escolhida, com os campos
    // limpos, para lançar o próximo
    setState(() {
      _sexo = null;
      _mae = null;
      _maeId = '';
      _maeController.clear();
      _sugestoes = [];
      _pai = null;
      _raca = null;
      _pelagem = null;
      _pesoController.clear();
      _maeInvalida = false;
      _descNovoNascimento = '';
      _coberturaId = '';
      _itemCobertura = '';
      _dataInseminacao = '';
      _diasNascimento = '';
      _tipoGravacao = 0;
      _rotuloMonta = 'Estação de Monta:';
    });
    await _carregarParametros();
    await _carregarRegistrosHoje();
    _marcarMae();
  }

  /// Deixa o Nº Mãe (Nº Fêmea) marcado para digitação, mas sem abrir o
  /// teclado: o usuário vê por onde começar; o toque no campo abre o
  /// teclado.
  void _marcarMae() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_maeFoco.canRequestFocus) return;
      _maeFoco.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      });
    });
  }

  // ---------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Mapa de Gado - Nascimento',
          style: TextStyle(fontSize: 18, color: Colors.white),
        ),
        backgroundColor: _azul,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: const [IndicadorConectividadeWidget(), SizedBox(width: 8)],
      ),
      body: ListView(
        // embaixo, também a altura da barra de navegação do celular: a tela
        // é desenhada por trás dela e a última linha da lista ficava
        // escondida ali, mesmo rolando até o fim
        padding: EdgeInsets.fromLTRB(
          6,
          6,
          6,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          // Puxar para baixo a partir da tarja azul atualiza a tela (com
          // internet) — ver _atualizarTela.
          PuxarParaAtualizarWidget(
            onAtualizar: _atualizarTela,
            habilitado: !_gravando,
            child: _cabecalho(),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
            child: _rotuloObrigatorio('Selecione uma opção', 14),
          ),
          Row(
            children: [
              for (final o in _opcoes)
                Expanded(
                  // mais espaço para o texto mais comprido
                  flex: o.value.length + 4,
                  child: _radio(
                    o.value,
                    marcado: _opcao == o.key,
                    aoTocar: () => _escolherOpcao(o.key),
                  ),
                ),
            ],
          ),
          if (_opcao != null) ...[
            const SizedBox(height: 6),
            // Painel cinza com as caixas brancas: mesmo padrão dos modais
            // de Morte e Nutrição.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._avisosDoTopo(),
                  if (_opcao == 'N')
                    ..._camposNascimento()
                  else
                    ..._camposOcorrencia(),
                  // no Nascimento o Confirmar fica na linha do Peso
                  if (_opcao != 'N') ...[
                    const SizedBox(height: 10),
                    _botao(
                      _gravando ? 'Aguarde...' : 'Confirmar',
                      _verde,
                      _confirmar,
                    ),
                  ],
                ],
              ),
            ),
          ] else
            Divider(color: Colors.grey[200], height: 16),
          // Fora do card cinza: logo abaixo das opções e, com uma opção
          // escolhida, depois dos campos.
          if (_registrosHoje.isNotEmpty) ...[
            const SizedBox(height: 12),
            _listaRegistrosHoje(),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Registros de Hoje: nascimentos, abortos, absorções e natimortos da
  // fazenda INCLUÍDOS hoje no sistema, mesmo com nascimento em data
  // anterior (servidor — o Nascimento só funciona online). Animal que já
  // morreu ou foi vendido aparece em vermelho.
  // ---------------------------------------------------------------------

  List<Map<String, dynamic>> _registrosHoje = [];

  /// "Puxar para atualizar" pela tarja azul: busca de novo a lista do dia,
  /// os selects (Pai, Raça e Pelagem) e o cadastro de animais. O próximo Nº
  /// do Animal e a estação só são relidos sem opção escolhida, para não
  /// trocar o que já está na tela; o que foi escolhido/digitado continua.
  Future<void> _atualizarTela() async {
    final tarefas = <Future<void>>[
      _carregarRegistrosHoje(),
      _carregarListas(),
      _carregarCadastro(),
      if (_opcao == null) _carregarParametros(),
    ];
    await Future.wait(tarefas);
  }

  Future<void> _carregarRegistrosHoje() async {
    final dados = await MapaGadoSyncService.instance.consultarNascimento({
      'acao': 'registros_hoje',
      'bd': widget.bd,
      'fazenda': widget.fazendaId,
    });
    if (!mounted || dados == null) return;
    final registros = [
      for (final r in (dados['registros'] as List? ?? const []))
        Map<String, dynamic>.from(r as Map),
    ];
    // Mesma ordem do form_nascimento_animais.php do web: data da maior para
    // a menor e, na mesma data, o número do animal do maior para o menor
    // (Aborto, Absorção e Natimorto, sem número, ficam por último).
    int numero(Map<String, dynamic> r) =>
        int.tryParse(
          RegExp(r'(\d+)$').firstMatch(r['animal']?.toString() ?? '')?[1] ??
              '',
        ) ??
        0;
    registros.sort((a, b) {
      final porData = (b['data']?.toString() ?? '').compareTo(
        a['data']?.toString() ?? '',
      );
      return porData != 0 ? porData : numero(b).compareTo(numero(a));
    });
    setState(() => _registrosHoje = registros);
  }

  static const _colunasRegistros = [
    ('Nº Animal', 10),
    ('Data', 12),
    ('Sexo', 5),
    ('Mãe', 8),
    ('Pasto', 12),
  ];

  /// [vermelho]: o animal já morreu ou foi vendido (como a lista de
  /// nascimentos do web, em vermelho).
  Widget _linhaRegistro(
    List<String> valores, {
    bool cabecalho = false,
    bool vermelho = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(
        children: [
          for (var i = 0; i < valores.length; i++)
            Expanded(
              flex: _colunasRegistros[i].$2,
              child: Text(
                valores[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: i == 2 ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  fontSize: cabecalho ? 11 : 12,
                  color: cabecalho
                      ? _corRotulo
                      : vermelho
                      ? Colors.red
                      : Colors.black87,
                  fontWeight: cabecalho ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _listaRegistrosHoje() {
    String dataBr(String iso) {
      final d = DateTime.tryParse(iso);
      return d == null ? iso : _formatar(d);
    }

    // Sem moldura, no mesmo visual da lista de pesagens da tela de Pesagem.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // mesmo título de "Pesagens sem finalizar"
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Text(
            'Registros de Hoje',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.blue[300],
            ),
          ),
        ),
        _linhaRegistro([
          for (final c in _colunasRegistros) c.$1,
        ], cabecalho: true),
        Divider(height: 1, color: Colors.grey.shade300),
        // Todas as linhas, sem rolagem própria: quem rola é a tela inteira
        // (a caixa de altura fixa escondia parte dos animais lá embaixo).
        for (var i = 0; i < _registrosHoje.length; i++) ...[
          if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
          _linhaRegistro([
            (_registrosHoje[i]['animal'] ?? '').toString(),
            dataBr((_registrosHoje[i]['data'] ?? '').toString()),
            (_registrosHoje[i]['sexo'] ?? '').toString(),
            (_registrosHoje[i]['mae'] ?? '').toString(),
            (_registrosHoje[i]['pasto'] ?? '').toString(),
          ], vermelho: _registrosHoje[i]['baixado'] == true),
        ],
      ],
    );
  }

  List<Widget> _avisosDoTopo() => [
    if (_atualizandoCadastro) ...[
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            'Atualizando o cadastro de animais...',
            style: TextStyle(fontSize: 12, color: _corRotulo),
          ),
        ],
      ),
      const SizedBox(height: 8),
    ],
    if (!_temCadastro && !_atualizandoCadastro) ...[
      _aviso(
        'O cadastro de animais desta fazenda ainda não foi baixado neste '
        'aparelho. Atualize os dados com internet.',
      ),
      const SizedBox(height: 8),
    ],
    if (_falhaListas && _opcao == 'N') ...[
      GestureDetector(
        onTap: _carregarListas,
        child: _aviso(
          'Não foi possível buscar as listas de Pai, Raça e Pelagem. '
          'Toque aqui para tentar de novo.',
        ),
      ),
      const SizedBox(height: 8),
    ],
  ];

  /// Lista de aproximação e descrição da fêmea, logo abaixo da linha do
  /// campo.
  List<Widget> _abaixoDaMae() => [
    if (_sugestoes.isNotEmpty) _listaSugestoes(),
    if (_consultandoMae) ...[
      const SizedBox(height: 6),
      Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            'Consultando a fêmea...',
            style: TextStyle(fontSize: 12, color: _corRotulo),
          ),
        ],
      ),
    ],
  ];

  /// Opção Nascimento:
  ///   1. Data Nascimento
  ///   2. Nº Mãe e Pai Nº
  ///   3. Nº Animal e Monta
  ///   (Sexo)
  ///   4. Raça e Pelagem
  ///   5. Peso e Confirmar
  List<Widget> _camposNascimento() => [
    Row(
      children: [
        Expanded(child: _campoData('* Data Nascimento')),
        const SizedBox(width: 8),
        const Expanded(child: SizedBox()),
      ],
    ),
    const SizedBox(height: 8),
    Row(
      children: [
        Expanded(child: _campoMae('* Nº Mãe')),
        const SizedBox(width: 8),
        Expanded(child: _campoPai()),
      ],
    ),
    ..._abaixoDaMae(),
    const SizedBox(height: 8),
    Row(
      children: [
        // Código Alfa só aparece quando a fazenda tem um nos Parâmetros
        // de Nascimento (igual ao web).
        if (_mostraAlfa) ...[
          Expanded(
            flex: 5,
            child: _campoTexto('Cód. Alfa', _alfaController, maximo: 4),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          flex: _mostraAlfa ? 7 : 12,
          child: _campoTexto('Nº Animal', _animalController, numerico: true),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 12,
          child: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_rotuloMonta $_estacao'.trim(),
                  style: TextStyle(fontSize: 13, color: _corRotulo),
                ),
                if (_descNovoNascimento.isNotEmpty)
                  Text(
                    _descNovoNascimento,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
    const SizedBox(height: 8),
    _campoSexo(),
    const SizedBox(height: 8),
    Row(
      children: [
        Expanded(
          child: _seletor(
            '* Raça',
            _raca,
            _racas,
            (v) => setState(() => _raca = v),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _seletor(
            'Pelagem',
            _pelagem,
            _pelagens,
            (v) => setState(() => _pelagem = v),
          ),
        ),
      ],
    ),
    const SizedBox(height: 8),
    Row(
      children: [
        Expanded(child: _campoTexto('* Peso', _pesoController, numerico: true)),
        const SizedBox(width: 8),
        Expanded(
          child: _botao(
            _gravando ? 'Aguarde...' : 'Confirmar',
            _verde,
            _confirmar,
            altura: 56,
          ),
        ),
      ],
    ),
  ];

  /// Opções Aborto, Absorção e Natimorto (iguais no web).
  List<Widget> _camposOcorrencia() => [
    Row(
      children: [
        Expanded(child: _campoData('* Data Ocorrência')),
        const SizedBox(width: 8),
        Expanded(child: _campoMae('* Nº Fêmea')),
      ],
    ),
    ..._abaixoDaMae(),
    const SizedBox(height: 8),
    _campoSexo(),
  ];

  /// Tarja azul no mesmo padrão da tela do pasto, com a fazenda e o pasto
  /// na mesma linha (a fonte encolhe um pouco se o nome for comprido).
  Widget _cabecalho() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '${widget.nomeFazenda}  -  ${widget.nomePasto}',
          maxLines: 1,
          softWrap: false,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.blue,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _rotuloObrigatorio(String texto, double fonte) => Text.rich(
    TextSpan(
      style: TextStyle(fontSize: fonte, color: _corRotulo),
      children: [
        const TextSpan(
          text: '* ',
          style: TextStyle(color: Colors.red),
        ),
        TextSpan(text: texto),
      ],
    ),
  );

  Widget _aviso(String texto) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF2DEDE),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      texto,
      style: const TextStyle(fontSize: 13, color: Color(0xFFA94442)),
    ),
  );

  Widget _radio(
    String texto, {
    required bool marcado,
    required VoidCallback aoTocar,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: aoTocar,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        // Sempre em uma linha: a fonte encolhe um pouco se não couber.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                marcado ? Icons.radio_button_checked : Icons.radio_button_off,
                color: marcado ? _azul : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 4),
              Text(texto, style: TextStyle(fontSize: 14, color: _corRotulo)),
            ],
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Campos — mesmo padrão dos modais de Morte e Nutrição
  // -----------------------------------------------------------------------

  Widget _caixa({required Widget child, bool erro = false}) => Container(
    height: 56,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: erro ? Border.all(color: Colors.red) : null,
    ),
    child: child,
  );

  Widget _campoTexto(
    String rotulo,
    TextEditingController controller, {
    bool numerico = false,
    bool decimal = false,
    int? maximo,
  }) => CampoTextoTopo(
    rotulo: rotulo,
    corRotulo: _corRotulo,
    controller: controller,
    keyboardType: decimal
        ? const TextInputType.numberWithOptions(decimal: true)
        : numerico
        ? TextInputType.number
        : TextInputType.text,
    inputFormatters: [
      if (numerico) FilteringTextInputFormatter.digitsOnly,
      if (decimal) FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      if (maximo != null) LengthLimitingTextInputFormatter(maximo),
    ],
    textCapitalization: TextCapitalization.characters,
  );

  Widget _campoMae(String rotulo) => CampoTextoTopo(
    rotulo: rotulo,
    corRotulo: _corRotulo,
    controller: _maeController,
    focusNode: _maeFoco,
    enabled: _temCadastro,
    erro: _maeInvalida,
    // teclado numérico: a mãe é procurada pelo número
    keyboardType: TextInputType.number,
    textCapitalization: TextCapitalization.characters,
    onTap: _aoTocarMae,
    onChanged: _aoDigitarMae,
  );

  /// Lista de aproximação logo abaixo do campo (como na Morte e na
  /// Pesagem).
  Widget _listaSugestoes() => Container(
    margin: const EdgeInsets.only(top: 2),
    constraints: const BoxConstraints(maxHeight: 220),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
    ),
    child: ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: _sugestoes.length,
      itemBuilder: (context, i) {
        final animal = _sugestoes[i];
        return ListTile(
          dense: true,
          title: Text(
            _exibicao(animal['codigo']?.toString() ?? ''),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          onTap: () => _escolherMae(animal),
        );
      },
    ),
  );

  Widget _campoData(String rotulo) => CampoValorTopo(
    rotulo: rotulo,
    corRotulo: _corRotulo,
    valor: _formatar(_data),
    icone: Icon(Icons.calendar_month, color: _corRotulo, size: 20),
    onTap: _escolherData,
  );

  /// "* Sexo" com Macho e Fêmea, dentro de uma caixa como os outros campos.
  Widget _campoSexo() => _caixa(
    child: Padding(
      padding: const EdgeInsets.only(left: 12, right: 6),
      child: Row(
        children: [
          Text('* Sexo', style: TextStyle(fontSize: 14, color: _corRotulo)),
          const SizedBox(width: 14),
          Expanded(
            child: _radio(
              'Macho',
              marcado: _sexo == 'M',
              aoTocar: () => setState(() => _sexo = 'M'),
            ),
          ),
          Expanded(
            child: _radio(
              'Fêmea',
              marcado: _sexo == 'F',
              aoTocar: () => setState(() => _sexo = 'F'),
            ),
          ),
        ],
      ),
    ),
  );

  /// "Pai Nº": mesmo desenho dos outros selects (rótulo no topo e o valor
  /// em negrito quando escolhido).
  Widget _campoPai() => CampoValorTopo(
    rotulo: 'Pai Nº',
    corRotulo: _corRotulo,
    valor: _pai?.texto ?? '',
    onTap: _escolherPai,
    icone: _carregandoListas
        ? const Padding(
            padding: EdgeInsets.only(right: 6),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : Icon(Icons.arrow_drop_down, color: _corRotulo),
  );

  Widget _seletor(
    String rotulo,
    String? valor,
    List<MapEntry<String, String>> opcoes,
    ValueChanged<String> aoMudar,
  ) => IgnorePointer(
    // sem opções (listas ainda chegando) o toque não abre nada
    ignoring: opcoes.isEmpty,
    child: SeletorCampoWidget<String>(
      rotulo: rotulo,
      corRotulo: _corRotulo,
      destaque: true,
      valor: valor,
      opcoes: opcoes,
      onChanged: aoMudar,
    ),
  );

  Widget _botao(
    String texto,
    Color cor,
    VoidCallback aoTocar, {
    double altura = 45,
  }) => SizedBox(
    height: altura,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: cor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: aoTocar,
      child: Text(
        texto,
        style: const TextStyle(fontSize: 15, color: Colors.white),
      ),
    ),
  );
}

/// Botão de um modal "Nascimento - Mensagem".
class _BotaoAviso {
  final String texto;
  final Color cor;
  final String acao;
  const _BotaoAviso(this.texto, this.cor, this.acao);
}

/// Lista do "Pai Nº" com busca, nos grupos SEMEM e ANIMAIS do web. A
/// primeira linha ("...") devolve uma opção de id vazio (sem pai).
class _ListaPaiDialog extends StatefulWidget {
  final List<_OpcaoPai> opcoes;
  final String? selecionado;
  final Color corRotulo;
  final Color corTitulo;
  final Color corFechar;

  const _ListaPaiDialog({
    required this.opcoes,
    required this.selecionado,
    required this.corRotulo,
    required this.corTitulo,
    required this.corFechar,
  });

  @override
  State<_ListaPaiDialog> createState() => _ListaPaiDialogState();
}

class _ListaPaiDialogState extends State<_ListaPaiDialog> {
  String _termo = '';

  /// Linhas da lista: String = título de grupo; _OpcaoPai = opção.
  List<Object> get _linhas {
    final t = _termo.trim().toUpperCase();
    final linhas = <Object>[];
    if (t.isEmpty) linhas.add(const _OpcaoPai('', '...', ''));
    String? grupo;
    for (final o in widget.opcoes) {
      if (t.isNotEmpty && !o.texto.toUpperCase().contains(t)) continue;
      if (o.grupo != grupo) {
        grupo = o.grupo;
        linhas.add(grupo);
      }
      linhas.add(o);
    }
    return linhas;
  }

  @override
  Widget build(BuildContext context) {
    final linhas = _linhas;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pai Nº',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: widget.corTitulo),
            ),
            const SizedBox(height: 10),
            Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                onChanged: (v) => setState(() => _termo = v),
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Buscar...',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                  prefixIcon: Icon(Icons.search, size: 20),
                  prefixIconConstraints: BoxConstraints(minWidth: 40),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: linhas.isEmpty
                    ? Center(
                        child: Text(
                          'Nenhum resultado.',
                          style: TextStyle(color: widget.corRotulo),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: linhas.length,
                        itemBuilder: (context, i) {
                          final linha = linhas[i];
                          if (linha is String) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                              child: Text(
                                linha,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: widget.corRotulo,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          }
                          final o = linha as _OpcaoPai;
                          final marcado =
                              o.id.isNotEmpty && o.id == widget.selecionado;
                          return InkWell(
                            onTap: () => Navigator.pop(context, o),
                            child: Container(
                              color: marcado ? Colors.grey.shade200 : null,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 11,
                              ),
                              child: Text(
                                o.texto,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 45,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.corFechar,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Voltar',
                  style: TextStyle(fontSize: 15, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
