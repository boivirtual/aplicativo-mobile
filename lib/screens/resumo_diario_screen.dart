import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/daos/mapa_gado_dao.dart';
import '../services/connectivity_service.dart';
import '../services/resumo_diario_service.dart';
import '../utils/app_alert.dart';
import '../utils/estilo_app.dart';
import '../widgets/cabecalho_fazenda_widget.dart';
import '../widgets/campo_topo_widget.dart';
import '../widgets/tarja_fazenda_widget.dart';
import 'aplicacao_modal.dart';
import 'tratamento_modal.dart';
import '../widgets/indicador_conectividade_widget.dart';
import '../widgets/seletor_campo_widget.dart';

/// "Resumo Diário da Fazenda": conferência, por usuário logado, dos
/// serviços feitos na fazenda no dia. São 10 seções, mostradas uma de cada
/// vez; o usuário só avança (Próximo) depois de preencher a seção atual.
///
/// Por enquanto só a Seção 1 (Identificação): data (hoje, pode ser anterior,
/// nunca futura), fazenda (as do usuário; uma só já vem escolhida) e o
/// responsável (o usuário logado, sem digitar). O Próximo ainda não avança.
class ResumoDiarioScreen extends StatefulWidget {
  /// Seta da Seção 1: volta para a Home do rodapé (null = fecha a tela).
  final VoidCallback? onBack;

  const ResumoDiarioScreen({super.key, this.onBack});

  @override
  State<ResumoDiarioScreen> createState() => _ResumoDiarioScreenState();
}

class _ResumoDiarioScreenState extends State<ResumoDiarioScreen>
    with WidgetsBindingObserver {
  static const _azul = Color(0xFF18385F);
  static const _azulBotao = Color(0xFF007AFF);
  static final _corRotulo = Colors.blueGrey[800]!;

  static const _totalSecoes = 10;

  /// 0 = tela inicial (escolha da fazenda), antes das seções.
  int _secao = 0;

  // Seção 2 — Conferência de Rebanho
  String? _conferiuGado; // 'todo', 'parte', 'nao'
  final _esperadosController = TextEditingController();
  final _encontradosController = TextEditingController();
  String? _conferiuPrenhas; // 'sim', 'nao', 'sem'
  final _obsRebanhoController = TextEditingController();

  // Seção 3 — Sanidade Animal: "Adicionar Tratamento" ou "Nenhum animal
  // doente ou medicado hoje" (um exclui o outro).
  bool _nenhumDoente = false;

  /// Tratamentos adicionados (a tela de inclusão vem nas próximas etapas).
  final List<Map<String, dynamic>> _tratamentos = [];

  /// "Adicionar Tratamento": abre o modal "Tratamento N" (N = próximo
  /// número); ao confirmar, entra na lista abaixo do botão.
  Future<void> _adicionarTratamento({int? editar}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final indice = editar ?? _tratamentos.length;
    final dados = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TratamentoModal(
        numero: indice + 1,
        dados: editar == null ? null : _tratamentos[editar],
        bd: _bd ?? '',
        fazenda: _fazenda ?? '',
      ),
    );
    if (dados == null || !mounted) return;
    setState(() {
      if (editar == null) {
        _tratamentos.add(dados);
      } else {
        _tratamentos[editar] = dados;
      }
    });
  }

  Future<void> _excluirTratamento(int indice) async {
    if (await _confirmarExclusao('Tratamento', indice) && mounted) {
      setState(() => _tratamentos.removeAt(indice));
    }
  }

  /// "Excluir <nome> N?" — mesmo modelo do "Excluir Item" da Pesagem.
  Future<bool> _confirmarExclusao(String nome, int indice) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        // mesmo modelo do "Excluir Item" da Pesagem: o NÃO em evidência
        title: Text(
          'Excluir $nome',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Confirma a exclusão ${nome == 'Aplicação' ? 'da' : 'do'} '
          '$nome ${indice + 1}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'NÃO',
              style: TextStyle(
                color: Colors.blue,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'SIM',
              style: TextStyle(color: Colors.blue, fontSize: 16),
            ),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Lista dos registros confirmados ("Tratamento N", "Aplicação N"...),
  /// cada um com editar e lixeira.
  List<Widget> _listaRegistros(
    String nome,
    int quantidade,
    void Function(int) editar,
    void Function(int) excluir,
  ) => [
    for (var i = 0; i < quantidade; i++)
      Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.only(left: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFCFD8DC)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$nome ${i + 1}',
                style: _textoGrosso(_corRotulo).copyWith(fontSize: 15),
              ),
            ),
            IconButton(
              tooltip: 'Editar',
              // azul do btn-primary (Bootstrap 3)
              icon: const Icon(Icons.edit_outlined, color: Color(0xFF337AB7)),
              onPressed: () => editar(i),
            ),
            IconButton(
              tooltip: 'Excluir',
              icon: const Icon(Icons.delete_outline, color: Color(0xFF337AB7)),
              onPressed: () => excluir(i),
            ),
          ],
        ),
      ),
  ];

  // Seção 5 — Atividades no Curral: "Teve atividade no curral hoje?"; com
  // "Sim", as atividades, as categorias trabalhadas, a quantidade e a
  // observação.
  String? _teveCurral; // 'sim' ou 'nao'
  final Set<String> _atividadesCurral = {};
  final Set<String> _categoriasCurral = {};
  final _qtdeCurralController = TextEditingController();
  final _obsCurralController = TextEditingController();

  static const _atividadesDoCurral = <(String, String, IconData)>[
    ('pesagem', 'Pesagem de animais', Icons.scale_outlined),
    ('separacao', 'Separação de lotes', Icons.call_split),
    ('desmama', 'Desmama', Icons.baby_changing_station_outlined),
    ('tatuagem', 'Tatuagem ou marcação', Icons.sell_outlined),
    ('descorna', 'Descorna (mochação)', Icons.content_cut),
    ('protocolo', 'Protocolo de Reprodução', Icons.assignment_outlined),
    ('diagnostico', 'Diagnóstico', Icons.biotech_outlined),
    (
      'medicamentos',
      'Aplicação de Medicamentos (individual, coletivo, cura de umbigo)',
      Icons.vaccines_outlined,
    ),
  ];

  static const _categoriasAnimal = [
    'Bezerros 0–7m',
    'Bezerros 8–12m',
    'Novilhas 13–24m',
    'Garrotes 13–24m',
    'Vacas',
    'Bois',
    'CAVALOS',
  ];

  // Seção 4 — Vacinas, Vermífugos e Carrapaticidas: "Adicionar Aplicação"
  // ou "Nenhuma aplicação de vacina ou vermífugo hoje" (como a Seção 3).
  bool _nenhumaAplicacao = false;

  /// Aplicações adicionadas (a tela "Adicionar Aplicação" vem depois).
  final List<Map<String, dynamic>> _aplicacoes = [];

  /// "Adicionar Aplicação": abre o modal "Aplicação N" (N = próximo
  /// número); ao confirmar, entra na lista abaixo do botão.
  Future<void> _adicionarAplicacao({int? editar}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final indice = editar ?? _aplicacoes.length;
    final dados = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AplicacaoModal(
        numero: indice + 1,
        dados: editar == null ? null : _aplicacoes[editar],
      ),
    );
    if (dados == null || !mounted) return;
    setState(() {
      if (editar == null) {
        _aplicacoes.add(dados);
      } else {
        _aplicacoes[editar] = dados;
      }
    });
  }

  Future<void> _excluirAplicacao(int indice) async {
    if (await _confirmarExclusao('Aplicação', indice) && mounted) {
      setState(() => _aplicacoes.removeAt(indice));
    }
  }

  // pastos onde está a diferença (quando Esperados ≠ Encontrados)
  final Set<int> _pastosDiferenca = {};
  List<MapEntry<int, String>> _pastosFazenda = [];
  String? _pastosDaFazenda; // fazenda dos pastos carregados

  int? get _esperados => int.tryParse(_esperadosController.text.trim());
  int? get _encontrados => int.tryParse(_encontradosController.text.trim());

  /// Encontrados − Esperados (null enquanto falta um dos dois).
  int? get _diferenca {
    final e = _esperados, n = _encontrados;
    return e == null || n == null ? null : n - e;
  }

  /// Pastos da fazenda escolhida (do mapa guardado no aparelho).
  Future<void> _carregarPastos() async {
    final fazenda = _fazenda;
    final bd = _bd;
    if (fazenda == null || bd == null || _pastosDaFazenda == fazenda) return;
    final pastos = await MapaGadoDao.instance.pastos(
      bd,
      int.tryParse(fazenda) ?? 0,
      incluirForaTabuleiro: true,
    );
    if (!mounted) return;
    setState(() {
      _pastosDaFazenda = fazenda;
      _pastosFazenda = [for (final p in pastos) MapEntry(p.id, p.descricao)];
      _pastosDiferenca.removeWhere(
        (id) => !_pastosFazenda.any((p) => p.key == id),
      );
    });
  }

  /// Lista para marcar um ou vários pastos.
  Future<void> _escolherPastos() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _carregarPastos();
    if (!mounted) return;
    if (_pastosFazenda.isEmpty) {
      await AppAlert.erro(
        context,
        'Os pastos desta fazenda ainda não foram baixados neste aparelho. '
        'Abra o Mapa de Gado com internet e tente de novo.',
      );
      return;
    }
    // Como o selectpicker do web: busca no topo e um toque marca/desmarca
    // a linha (fica destacada, com o ✓), sem caixinhas.
    final marcados = {..._pastosDiferenca};
    var busca = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final visiveis = [
            for (final p in _pastosFazenda)
              if (p.value.toUpperCase().contains(busca.toUpperCase())) p,
          ];
          return AlertDialog(
            title: const Text(
              'Em qual(is) pasto(s) está a diferença?',
              style: TextStyle(fontSize: 16, color: _azul),
            ),
            contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    onChanged: (v) => setModal(() => busca = v.trim()),
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'Buscar pasto...',
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: visiveis.length,
                      itemBuilder: (context, i) {
                        final p = visiveis[i];
                        final marcado = marcados.contains(p.key);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Material(
                            color: marcado
                                ? const Color(0xFFD6E8FA)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => setModal(() {
                                if (marcado) {
                                  marcados.remove(p.key);
                                } else {
                                  marcados.add(p.key);
                                }
                              }),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 11,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        p.value,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: marcado
                                              ? _azul
                                              : Colors.black87,
                                        ),
                                      ),
                                    ),
                                    if (marcado)
                                      const Icon(
                                        Icons.check,
                                        size: 18,
                                        color: _azulBotao,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('OK (${marcados.length})'),
              ),
            ],
          );
        },
      ),
    );
    if (ok == true && mounted) {
      setState(
        () => _pastosDiferenca
          ..clear()
          ..addAll(marcados),
      );
    }
  }

  /// Ao digitar os totais: se a diferença sumir (iguais ou incompletos), os
  /// pastos marcados são limpos — numa nova diferença, escolhe-se de novo.
  void _totaisMudaram() {
    setState(() {
      if ((_diferenca ?? 0) == 0) _pastosDiferenca.clear();
    });
  }

  /// Nomes dos pastos marcados, na ordem da lista.
  String get _nomesPastosDiferenca => [
    for (final p in _pastosFazenda)
      if (_pastosDiferenca.contains(p.key)) p.value,
  ].join(', ');

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _esperadosController.dispose();
    _encontradosController.dispose();
    _obsRebanhoController.dispose();
    _qtdeCurralController.dispose();
    _obsCurralController.dispose();
    super.dispose();
  }

  DateTime _data = _hoje();
  List<MapEntry<String, String>> _fazendas = [];
  String? _fazenda;

  /// Fazendas como vêm do login (o select e o modal de troca usam assim).
  List<dynamic> _fazendasLista = const [];

  /// Fazendas já lidas do aparelho (até lá, só o "carregando").
  bool _carregado = false;
  String _responsavel = '';

  /// Nome do usuário logado como veio do login (saudação da tela inicial).
  String _nomeUsuario = '';
  String? _bd;

  /// "Atividades do Dia" (Seção 1): o que o usuário fez hoje na fazenda.
  /// Muitas estão ligadas aos programas do app (Chuva, Mapa de Gado,
  /// Nascimento, Morte...). "Nenhuma das atividades" exclui as outras.
  static const _nenhuma = 'nenhuma';
  static const _atividades = <(String, String, IconData?, String?)>[
    ('choveu', 'Choveu', Icons.water_drop_outlined, null),
    ('mudei_pasto', 'Mudei o gado de pasto', Icons.swap_horiz, null),
    ('nutricao', 'Distribuí nutrição', Icons.grass, null),
    ('nascimento', 'Nascimento', Icons.child_care, null),
    (
      'aborto_natimorto',
      'Aborto / Natimorto',
      Icons.warning_amber_rounded,
      null,
    ),
    ('morte', 'Morreu animal', Icons.heart_broken_outlined, null),
    (_nenhuma, 'Nenhuma das atividades', Icons.block, null),
  ];
  final Set<String> _atividadesMarcadas = {};

  static DateTime _hoje() {
    final a = DateTime.now();
    return DateTime(a.year, a.month, a.day);
  }

  static String _formatar(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _carregar();
  }

  /// Teclado aberto? Lido direto da tela do aparelho: dentro do rodapé
  /// (main_container.dart) o Scaffold de fora já desconta o teclado e o
  /// MediaQuery daqui chega com o valor zerado.
  bool get _tecladoAberto => View.of(context).viewInsets.bottom > 0;

  /// O teclado abriu ou fechou: redesenha (mostra ou esconde a barra
  /// Anterior/Próximo).
  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  bool _estavaVisivel = false;

  /// O Resumo fica montado mesmo escondido (main_container.dart). Saiu da
  /// tela (seta ou rodapé) ainda na tela inicial: com mais de uma fazenda,
  /// a escolha é desfeita, para pedir a fazenda de novo ao voltar. Voltou
  /// para a tela inicial: a data volta para hoje e o dia anterior é
  /// conferido de novo.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visivel = TickerMode.of(context);
    if (_estavaVisivel && !visivel && _secao == 0 && _fazendas.length > 1) {
      _fazenda = null;
    }
    if (!_estavaVisivel && visivel && _secao == 0) {
      _data = _hoje();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _conferirDiaAnterior(),
      );
    }
    _estavaVisivel = visivel;
  }

  // Tela inicial — conferência do dia anterior à data escolhida (no
  // servidor, só online).
  bool _conferindoDia = false;

  /// true = o dia anterior ficou sem resumo: para tudo até o usuário
  /// escolher esse dia no calendário.
  bool _diaPendente = false;

  /// Não deu para conferir (sem internet ou falha): também para tudo.
  String? _erroConferencia;

  /// Só a última conferência vale (a data pode mudar no meio de uma).
  int _conferencia = 0;

  Future<void> _conferirDiaAnterior() async {
    final bd = _bd;
    final fazenda = _fazenda;
    if (!mounted || bd == null || fazenda == null) return;
    final minha = ++_conferencia;
    final data = _data;
    setState(() {
      _conferindoDia = true;
      _diaPendente = false;
      _erroConferencia = null;
    });
    // checagem da internet na hora (o Resumo Diário só funciona online)
    final nivel = await ConnectivityService.instance.verificarAgora();
    bool? pendente;
    String? erro;
    if (nivel == NivelConexao.semInternet) {
      erro =
          'Sem internet! O Resumo Diário só pode ser feito com o aplicativo '
          'online. Conecte-se à internet e tente novamente.';
    } else if (nivel == NivelConexao.internetRuim) {
      erro =
          'Internet ruim ou intermitente! O Resumo Diário só pode ser feito '
          'com o aplicativo online. Tente novamente quando a internet estiver '
          'estável.';
    } else {
      pendente = await ResumoDiarioService.instance.diaAnteriorPendente(
        bd,
        fazenda,
        data,
      );
      if (pendente == null) {
        erro =
            'Não foi possível conferir os resumos anteriores. Tente '
            'novamente.';
      }
    }
    if (!mounted || minha != _conferencia) return;
    setState(() {
      _conferindoDia = false;
      _diaPendente = pendente == true;
      _erroConferencia = erro;
    });
    // Dia anterior sem resumo: avisa num modal e, no OK, já abre o
    // calendário nesse dia (só com o Resumo na tela).
    if (_diaPendente && TickerMode.of(context)) {
      final dia = data.subtract(const Duration(days: 1));
      await _avisoDiaSemResumo(
        'Não foi registrado o resumo do dia ${_formatar(dia)}.',
      );
      if (!mounted || minha != _conferencia) return;
      await _escolherDataInicial(inicial: dia);
    }
  }

  /// Modal do dia sem resumo: fundo vermelho (btn-danger do web), fonte e
  /// ícone de atenção brancos, e OK. Feito aqui para não mexer no AppAlert,
  /// que é usado pelos outros programas.
  Future<void> _avisoDiaSemResumo(String mensagem) {
    const fundo = Color(0xFFD9534F);
    const texto = Colors.white;
    FocusManager.instance.primaryFocus?.unfocus();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: fundo,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: texto, size: 30),
            const SizedBox(width: 10),
            Text('Atenção', style: EstiloApp.negrito(18, texto)),
          ],
        ),
        content: Text(
          mensagem,
          style: const TextStyle(fontSize: 15, color: texto),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK', style: EstiloApp.negrito(15, texto)),
          ),
        ],
      ),
    );
  }

  /// Calendário da tela inicial: hoje ou uma data anterior (futura não
  /// pode); a cada data escolhida, confere o dia anterior a ela. [inicial]:
  /// dia já marcado ao abrir (o dia sem resumo, vindo do aviso).
  Future<void> _escolherDataInicial({DateTime? inicial}) async {
    final d = await showDatePicker(
      context: context,
      initialDate: inicial ?? _data,
      firstDate: DateTime(2000),
      lastDate: _hoje(),
      helpText: 'Data do resumo',
    );
    if (d == null || !mounted) return;
    setState(() => _data = d);
    await _conferirDiaAnterior();
  }

  /// "Hoje é o dia ..." (ou "Resumo do dia ..." com uma data anterior
  /// escolhida) + calendário e, embaixo, o erro da conferência (o aviso do
  /// dia anterior sem resumo é um modal, ver [_conferirDiaAnterior]).
  List<Widget> _dataDaTelaInicial() => [
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  fontSize: 17,
                  color: EstiloApp.azulBarra,
                ),
                children: [
                  TextSpan(
                    text: _data == _hoje() ? 'Hoje é o dia ' : 'Resumo do dia ',
                  ),
                  TextSpan(
                    text: _formatar(_data),
                    style: EstiloApp.negrito(17, EstiloApp.azulBarra),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.calendar_month,
              color: EstiloApp.azulIcone,
              size: 28,
            ),
            tooltip: 'Escolher a data',
            onPressed: _conferindoDia ? null : () => _escolherDataInicial(),
          ),
        ],
      ),
    ),
    if (_conferindoDia)
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text(
              'Conferindo os resumos anteriores...',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      )
    else if (_erroConferencia != null)
      _avisoTelaInicial(
        _erroConferencia!,
        acao: TextButton(
          onPressed: _conferirDiaAnterior,
          child: const Text('Tentar novamente'),
        ),
      ),
  ];

  /// Caixa vermelha de aviso (alert-danger do web).
  Widget _avisoTelaInicial(String texto, {Widget? acao}) => Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF2DEDE),
      border: Border.all(color: const Color(0xFFEBCCD1)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(texto, style: EstiloApp.negrito(15, const Color(0xFFA94442))),
        if (acao != null) acao,
      ],
    ),
  );

  Future<void> _carregar() async {
    final prefs = await SharedPreferences.getInstance();
    final fazendasJson = prefs.getString('userFazendas');
    final lista = fazendasJson == null
        ? const []
        : (json.decode(fazendasJson) as List);
    if (!mounted) return;
    setState(() {
      _nomeUsuario = (prefs.getString('userName') ?? '').trim();
      _responsavel = _nomeUsuario.toUpperCase();
      _bd = prefs.getString('userCNPJ');
      _fazendas = [
        for (final f in lista)
          MapEntry(
            (f as Map)['id'].toString(),
            f['nome'].toString().toUpperCase(),
          ),
      ];
      _fazendasLista = lista;
      // uma fazenda só: já vem escolhida
      if (_fazendas.length == 1) _fazenda = _fazendas.first.key;
      _carregado = true;
    });
    // já na tela quando terminou de carregar: confere o dia anterior
    if (TickerMode.of(context) && _secao == 0) await _conferirDiaAnterior();
  }

  String get _nomeFazenda => _fazendas
      .firstWhere(
        (f) => f.key == _fazenda,
        orElse: () => const MapEntry('', ''),
      )
      .value;

  /// Ícone de edição da tarja: modal para escolher outra fazenda (igual à
  /// Chuva).
  Future<void> _escolherOutraFazenda() async {
    final escolhida = await escolherFazendaModal(
      context,
      fazendas: _fazendasLista,
      fazendaSelecionada: _fazenda,
    );
    if (escolhida != null && escolhida != _fazenda && mounted) {
      setState(() => _fazenda = escolhida);
      await _conferirDiaAnterior();
    }
  }

  /// Fazenda escolhida no select da tela inicial: confere o dia anterior
  /// dela.
  void _selecionarFazenda(String? id) {
    setState(() => _fazenda = id);
    _conferirDiaAnterior();
  }

  /// Tela inicial do Resumo (antes das seções). Uma fazenda só: já vem na
  /// tarja azul. Mais de uma: primeiro o select (igual à Chuva); escolhida,
  /// a tarja azul com o ícone de edição para trocar.
  Widget _telaInicial() => Column(
    children: [
      if (_fazenda == null)
        CabecalhoFazendaWidget(
          fazendaSelecionada: _fazenda,
          fazendasCarregadas: _fazendasLista,
          onChanged: _selecionarFazenda,
          mostrarIcone: false,
          textoVazio: 'Selecione uma Fazenda',
        )
      else
        TarjaFazendaWidget(
          nomeFazenda: _nomeFazenda,
          temOutras: _fazendas.length > 1,
          onTrocar: _escolherOutraFazenda,
        ),
      // saudação: "Olá <usuário>!", com o nome em negrito, à esquerda; só
      // depois de escolher a fazenda
      if (_fazenda != null)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
          child: Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 20, color: EstiloApp.azulBarra),
              children: [
                const TextSpan(text: 'Olá '),
                TextSpan(
                  text: _nomeUsuario,
                  style: EstiloApp.negrito(20, EstiloApp.azulBarra),
                ),
                const TextSpan(text: '!'),
              ],
            ),
          ),
        ),
      if (_fazenda != null) ..._dataDaTelaInicial(),
      Expanded(
        child: _fazenda == null
            ? Center(
                child: Text(
                  'Selecione uma fazenda.',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    ],
  );

  /// Hoje ou uma data anterior; data futura não pode.
  Future<void> _escolherData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2000),
      lastDate: _hoje(),
      helpText: 'Data do registro',
    );
    if (d != null) setState(() => _data = d);
  }

  /// Só avança com a seção atual preenchida. Os dados de cada seção ficam
  /// guardados ao ir e voltar.
  Future<void> _proximo() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_secao == 2) {
      if (_conferiuGado == null) {
        await AppAlert.erro(context, 'Informe se conferiu o gado.');
        return;
      }
      if (_conferiuGado != 'nao') {
        if (_esperadosController.text.trim().isEmpty ||
            _encontradosController.text.trim().isEmpty) {
          await AppAlert.erro(
            context,
            'Informe o Total de Animais Esperados e o de Encontrados.',
          );
          return;
        }
      }
      final dif = _diferenca;
      if (_conferiuGado != 'nao' &&
          dif != null &&
          dif != 0 &&
          _pastosDiferenca.isEmpty) {
        await AppAlert.erro(
          context,
          'Informe em qual(is) pasto(s) está a diferença.',
        );
        return;
      }
      if (_conferiuPrenhas == null) {
        await AppAlert.erro(context, 'Informe se conferiu as vacas prenhas.');
        return;
      }
      setState(() => _secao = 3);
      return;
    }
    if (_secao == 3) {
      if (!_nenhumDoente && _tratamentos.isEmpty) {
        await AppAlert.erro(
          context,
          'Adicione um tratamento ou marque "Nenhum animal doente ou '
          'medicado hoje".',
        );
        return;
      }
      setState(() => _secao = 4);
      return;
    }
    if (_secao == 4) {
      if (!_nenhumaAplicacao && _aplicacoes.isEmpty) {
        await AppAlert.erro(
          context,
          'Adicione uma aplicação ou marque "Nenhuma aplicação de vacina ou '
          'vermífugo hoje".',
        );
        return;
      }
      setState(() => _secao = 5);
      return;
    }
    if (_secao == 5) {
      String? erro;
      if (_teveCurral == null) {
        erro = 'Responda se teve atividade no curral hoje.';
      } else if (_teveCurral == 'sim') {
        if (_atividadesCurral.isEmpty) {
          erro = 'Marque as Atividades Realizadas.';
        } else if (_categoriasCurral.isEmpty) {
          erro = 'Selecione a(s) Categoria(s) Trabalhada(s).';
        } else if ((int.tryParse(_qtdeCurralController.text.trim()) ?? 0) <=
            0) {
          erro = 'Informe a Quantidade de Animais.';
        }
      }
      if (erro != null) {
        await AppAlert.erro(context, erro);
        return;
      }
      // A Seção 6 vem nas próximas etapas.
      return;
    }
    if (_secao == 1) {
      if (_fazenda == null) {
        await AppAlert.erro(context, 'Selecione a Fazenda.');
        return;
      }
      if (_atividadesMarcadas.isEmpty) {
        await AppAlert.erro(
          context,
          'Marque pelo menos uma das Atividades do Dia (ou "Nenhuma das '
          'atividades").',
        );
        return;
      }
      setState(() => _secao = 2);
    }
  }

  void _anterior() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_secao > 1) setState(() => _secao--);
  }

  void _marcarAtividade(String chave, bool marcada) {
    setState(() {
      if (!marcada) {
        _atividadesMarcadas.remove(chave);
      } else if (chave == _nenhuma) {
        // "Nenhuma" desmarca as outras
        _atividadesMarcadas
          ..clear()
          ..add(_nenhuma);
      } else {
        _atividadesMarcadas
          ..remove(_nenhuma)
          ..add(chave);
      }
    });
  }

  /// Seta do título (e "voltar" do Android): volta para a seção anterior;
  /// da Seção 1 volta para a tela inicial; só da tela inicial sai para a
  /// Home.
  void _voltar() {
    if (_secao > 1) {
      _anterior();
    } else if (_secao == 1) {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _secao = 0);
    } else if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dentro do rodapé o Resumo fica montado mesmo escondido (ver
    // main_container.dart): escondido, não segura o "voltar" do Android.
    final visivel = TickerMode.of(context);
    return PopScope(
      canPop: !visivel || (_secao == 0 && widget.onBack == null),
      onPopInvokedWithResult: (saiu, _) {
        if (!saiu && visivel) _voltar();
      },
      child: _tela(context),
    );
  }

  Widget _tela(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Resumo Diário da Fazenda',
          style: TextStyle(fontSize: 18, color: Colors.white),
        ),
        backgroundColor: _azul,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _voltar,
        ),
        actions: const [IndicadorConectividadeWidget(), SizedBox(width: 8)],
      ),
      body: !_carregado
          ? const Center(child: CircularProgressIndicator())
          : _secao == 0
          ? _telaInicial()
          : Column(
              children: [
                _progresso(),
                // Parte fixa da seção (não rola): na Seção 1, a Identificação e o
                // título das Atividades do Dia.
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _fixoDaSecao(),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      // Só esta parte rola (na Seção 1, as Atividades do Dia)
                      ListView(
                        // espaço no fim para o último item passar do botão Próximo
                        // (que fica por cima, junto com a barra do celular)
                        padding: EdgeInsets.fromLTRB(
                          12,
                          0,
                          12,
                          _tecladoAberto
                              ? 16
                              : 96 + MediaQuery.of(context).padding.bottom,
                        ),
                        children: _rolavelDaSecao(),
                      ),
                      // Próximo sempre visível; a tela rola por trás dele. Com o
                      // teclado aberto ele sai da frente, para não cobrir o campo
                      // que está sendo digitado.
                      if (!_tecladoAberto)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: SafeArea(
                            top: false,
                            // o fundo branco vai até embaixo (atrás da barra do
                            // celular), para a lista não aparecer ali
                            bottom: false,
                            child: Container(
                              padding: EdgeInsets.fromLTRB(
                                12,
                                10,
                                12,
                                12 + MediaQuery.of(context).padding.bottom,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 6,
                                    offset: const Offset(0, -2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  // Anterior (btn-default) a partir da Seção 2
                                  if (_secao > 1) ...[
                                    Expanded(
                                      child: SizedBox(
                                        height: 48,
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFFE9ECEF,
                                            ),
                                            foregroundColor: const Color(
                                              0xFF333333,
                                            ),
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          onPressed: _anterior,
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.arrow_back, size: 20),
                                              SizedBox(width: 8),
                                              Text(
                                                'Anterior',
                                                style: TextStyle(fontSize: 16),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                  ] else
                                    const Spacer(),
                                  Expanded(
                                    child: SizedBox(
                                      height: 48,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _azulBotao,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                        onPressed: _proximo,
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'Próximo',
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: Colors.white,
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            Icon(Icons.arrow_forward, size: 20),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// Barra de progresso (seção atual de 10) e o título da seção.
  Widget _progresso() {
    return Container(
      width: double.infinity,
      // mesmo azul da tarja dos outros programas (Mapa de Gado, Pesagem)
      color: Color.alphaBlend(Colors.blue.withValues(alpha: 0.1), Colors.white),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _secao / _totalSecoes,
              minHeight: 10,
              color: _azulBotao,
              backgroundColor: const Color(0xFFD5DCE4),
            ),
          ),
          const SizedBox(height: 8),
          // "Seção 1 de 10" menor; o nome da seção em negrito
          Text.rich(
            TextSpan(
              style: const TextStyle(color: Colors.blue),
              children: [
                TextSpan(
                  text: 'Seção $_secao de $_totalSecoes — ',
                  style: const TextStyle(fontSize: 13),
                ),
                TextSpan(
                  text: _tituloDaSecao(_secao),
                  // a fonte do app só tem a versão fina: o traço é
                  // engrossado com "sombras" da mesma cor
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    shadows: [
                      Shadow(color: Colors.blue, offset: Offset(0.5, 0)),
                      Shadow(color: Colors.blue, offset: Offset(-0.5, 0)),
                      Shadow(color: Colors.blue, offset: Offset(0, 0.5)),
                    ],
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _tituloDaSecao(int secao) => switch (secao) {
    1 => 'Identificação/Atividades',
    2 => 'Conferência de Rebanho',
    3 => 'Sanidade Animal',
    4 => 'Vacinas, Vermífugos e Carrapaticidas',
    5 => 'Atividades no Curral',
    _ => '',
  };

  List<Widget> _camposDaSecao() => switch (_secao) {
    _ => _secaoIdentificacao(),
  };

  Widget _tituloAzul(String texto) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
    child: Text(
      texto,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: Colors.blue[300],
      ),
    ),
  );

  /// Parte fixa de cada seção (não rola).
  List<Widget> _fixoDaSecao() => switch (_secao) {
    2 => [_tituloAzul('Contagem de Animais Hoje')],
    3 => [_tituloAzul('Tratamentos Realizados Hoje')],
    4 => [_tituloAzul('Aplicações Realizadas Hoje')],
    5 => [_tituloAzul('O Que Foi Feito Hoje')],
    _ => [
      _tituloAzul('Identificação'),
      // painel cinza com as caixas brancas, como nas outras telas
      _painelCinza(_camposDaSecao()),
      _tituloAzul('Atividades do Dia'),
    ],
  };

  Widget _painelCinza(List<Widget> filhos) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.grey[200],
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: filhos,
    ),
  );

  /// Parte que rola em cada seção (por trás do botão Próximo).
  List<Widget> _rolavelDaSecao() => switch (_secao) {
    1 => _atividadesDoDia(),
    2 => _conferenciaRebanho(),
    3 => [
      // botão (sem caixa de marcar), pode ser tocado várias vezes; travado
      // com "Nenhum animal doente..." marcado
      _linhaMarcar(
        'Adicionar Tratamento',
        Icons.medical_services_outlined,
        false,
        (_) => _adicionarTratamento(),
        semCaixa: true,
        habilitado: !_nenhumDoente,
      ),
      ..._listaRegistros(
        'Tratamento',
        _tratamentos.length,
        (i) => _adicionarTratamento(editar: i),
        _excluirTratamento,
      ),
      // com pelo menos 1 tratamento na lista, o "Nenhum animal doente..."
      // fica escondido; volta quando todos forem excluídos
      if (_tratamentos.isEmpty) ...[
        const SizedBox(height: 8),
        _linhaMarcar(
          'Nenhum animal doente ou medicado hoje',
          Icons.verified_outlined,
          _nenhumDoente,
          (v) => setState(() => _nenhumDoente = v),
        ),
      ],
    ],
    4 => [
      // botão, pode ser tocado várias vezes; travado com "Nenhuma
      // aplicação..." marcado
      _linhaMarcar(
        'Adicionar Aplicação',
        Icons.vaccines_outlined,
        false,
        (_) => _adicionarAplicacao(),
        semCaixa: true,
        habilitado: !_nenhumaAplicacao,
      ),
      ..._listaRegistros(
        'Aplicação',
        _aplicacoes.length,
        (i) => _adicionarAplicacao(editar: i),
        _excluirAplicacao,
      ),
      // com pelo menos 1 aplicação na lista, o "Nenhuma aplicação..."
      // fica escondido; volta quando todas forem excluídas
      if (_aplicacoes.isEmpty) ...[
        const SizedBox(height: 8),
        _linhaMarcar(
          'Nenhuma aplicação de vacina ou vermífugo hoje',
          Icons.verified_outlined,
          _nenhumaAplicacao,
          (v) => setState(() => _nenhumaAplicacao = v),
        ),
      ],
    ],
    5 => _atividadesNoCurral(),
    _ => const [],
  };

  // ---------------------------------------------------------------------
  // Seção 5 — Atividades no Curral
  // ---------------------------------------------------------------------

  List<Widget> _atividadesNoCurral() => [
    _pergunta('Teve Atividade no Curral Hoje?'),
    _opcoes(
      const [
        ('sim', 'Sim', Icons.check_circle_outline),
        ('nao', 'Não', Icons.highlight_off),
      ],
      _teveCurral,
      (v) => setState(() {
        _teveCurral = v;
        // "Não": o que tinha sido marcado com "Sim" deixa de valer
        if (v == 'nao') {
          _atividadesCurral.clear();
          _categoriasCurral.clear();
          _qtdeCurralController.clear();
          _obsCurralController.clear();
        }
      }),
    ),
    if (_teveCurral == 'sim') ...[
      _pergunta('Atividades Realizadas'),
      for (final a in _atividadesDoCurral) ...[
        _linhaMarcar(
          a.$2,
          a.$3,
          _atividadesCurral.contains(a.$1),
          (v) => setState(() {
            if (v) {
              _atividadesCurral.add(a.$1);
            } else {
              _atividadesCurral.remove(a.$1);
            }
          }),
        ),
        const SizedBox(height: 8),
      ],
      _pergunta('Categorias Trabalhadas'),
      ..._listaMultipla(_categoriasAnimal, _categoriasCurral),
      const SizedBox(height: 14),
      _painelCinza([
        CampoTextoTopo(
          rotulo: 'Quantidade de Animais',
          altura: 80,
          corRotulo: _corRotulo,
          controller: _qtdeCurralController,
          dica: 'Ex: 45',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: 8),
        CampoTextoTopo(
          rotulo: 'Observações / Detalhes (descreva "Outras Atividades" aqui)',
          corRotulo: _corRotulo,
          controller: _obsCurralController,
          altura: null,
          linhas: 3,
          dica: 'Descreva o que foi realizado, produtos usados, lotes, etc.',
          textCapitalization: TextCapitalization.sentences,
        ),
      ]),
    ],
  ];

  /// Lista já aberta, mostrando todas as opções (como a Categoria Animal
  /// do Tratamento): um toque marca ou desmarca a linha (fica destacada,
  /// com o ✓); embaixo, os nomes marcados.
  List<Widget> _listaMultipla(List<String> opcoes, Set<String> marcados) => [
    Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 4),
      child: Text(
        'Toque para selecionar uma ou mais opções.',
        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
      ),
    ),
    Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCFD8DC)),
      ),
      child: Column(
        children: [
          for (final o in opcoes)
            Container(
              height: 44,
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 3),
              child: Material(
                color: marcados.contains(o)
                    ? const Color(0xFFD6E8FA)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    setState(() {
                      if (!marcados.remove(o)) marcados.add(o);
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            o,
                            style: TextStyle(
                              fontSize: 14,
                              color: marcados.contains(o)
                                  ? _azul
                                  : Colors.black87,
                            ),
                          ),
                        ),
                        if (marcados.contains(o))
                          const Icon(Icons.check, size: 18, color: _azulBotao),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: Text(
        marcados.isEmpty
            ? 'Nenhuma selecionada'
            : [
                for (final o in opcoes)
                  if (marcados.contains(o)) o,
              ].join(', '),
        style: TextStyle(
          fontSize: 13,
          fontStyle: FontStyle.italic,
          color: marcados.isEmpty ? Colors.grey[600] : _corRotulo,
        ),
      ),
    ),
  ];

  // ---------------------------------------------------------------------
  // Seção 2 — Conferência de Rebanho
  // ---------------------------------------------------------------------

  Widget _pergunta(String texto) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
    child: Text(
      texto,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: Color(0xFF455A64),
      ),
    ),
  );

  static TextStyle _textoGrosso(Color cor) => TextStyle(
    fontSize: 13,
    height: 1.15,
    fontWeight: FontWeight.w900,
    color: cor,
    shadows: [
      Shadow(color: cor, offset: const Offset(0.4, 0)),
      Shadow(color: cor, offset: const Offset(-0.4, 0)),
      Shadow(color: cor, offset: const Offset(0, 0.4)),
    ],
  );

  /// Opções lado a lado, no mesmo visual das Atividades do Dia: fundo
  /// branco e borda cinza; a escolhida fica com fundo azul claro e borda
  /// azul. Ícone azul no centro e o texto embaixo.
  Widget _opcoes(
    List<(String, String, IconData)> opcoes,
    String? escolhida,
    ValueChanged<String> aoEscolher,
  ) {
    const azulIcone = Color(0xFF228cb9);
    return Row(
      children: [
        for (var i = 0; i < opcoes.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus();
                aoEscolher(opcoes[i].$1);
              },
              child: Container(
                // mais quadradas, como no modelo
                height: 96,
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                decoration: BoxDecoration(
                  color: escolhida == opcoes[i].$1
                      ? const Color(0xFFE3F2FD)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: escolhida == opcoes[i].$1
                        ? _azulBotao
                        : const Color(0xFFCFD8DC),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(opcoes[i].$3, size: 28, color: azulIcone),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Center(
                        child: Text(
                          opcoes[i].$2,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          // a fonte do app só tem a versão fina: o traço é
                          // engrossado com "sombras" da mesma cor
                          style: _textoGrosso(_corRotulo),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _conferenciaRebanho() => [
    _pergunta('Conferiu o Gado?'),
    _opcoes(
      const [
        ('todo', 'Gado Todo', Icons.done_all),
        ('parte', 'Parte do Gado', Icons.rule),
        ('nao', 'Não Conferi', Icons.block),
      ],
      _conferiuGado,
      (v) => setState(() => _conferiuGado = v),
    ),
    // os totais só com "Gado Todo" ou "Parte do Gado"
    if (_conferiuGado == 'todo' || _conferiuGado == 'parte') ...[
      const SizedBox(height: 10),
      _painelCinza([
        CampoTextoTopo(
          rotulo: '* Totais de Animais Esperados',
          rotuloNegrito: 'Esperados',
          altura: 80,
          corRotulo: _corRotulo,
          controller: _esperadosController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => _totaisMudaram(),
        ),
        const SizedBox(height: 8),
        CampoTextoTopo(
          rotulo: '* Totais de Animais Encontrados',
          rotuloNegrito: 'Encontrados',
          altura: 80,
          corRotulo: _corRotulo,
          controller: _encontradosController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => _totaisMudaram(),
        ),
        // Totais diferentes: a diferença (só leitura) e os pastos
        if ((_diferenca ?? 0) != 0) ...[
          const SizedBox(height: 8),
          CampoValorTopo(
            rotulo: _diferenca! < 0 ? 'Quantos Faltaram' : 'Quantos Sobraram',
            altura: 80,
            corRotulo: _corRotulo,
            valor: '${_diferenca!.abs()}',
          ),
          const SizedBox(height: 8),
          CampoValorTopo(
            rotulo: '* Em qual(is) pasto(s) está a diferença?',
            corRotulo: _corRotulo,
            valor: _pastosDiferenca.isEmpty
                ? ''
                : '${_pastosDiferenca.length} pasto(s) selecionado(s)',
            icone: Icon(Icons.arrow_drop_down, color: _corRotulo),
            onTap: _escolherPastos,
          ),
          if (_pastosDiferenca.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(
                _nomesPastosDiferenca,
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: _corRotulo,
                ),
              ),
            ),
        ],
      ]),
    ],
    _pergunta('Conferiu as Vacas Prenhas?'),
    _opcoes(
      const [
        ('sim', 'Sim', Icons.check_circle_outline),
        ('nao', 'Não', Icons.highlight_off),
        ('sem', 'Sem\nVacas Prenhas', Icons.do_not_disturb_on_outlined),
      ],
      _conferiuPrenhas,
      (v) => setState(() => _conferiuPrenhas = v),
    ),
    const SizedBox(height: 14),
    _painelCinza([
      CampoTextoTopo(
        rotulo: 'Observação Sobre o Rebanho',
        corRotulo: _corRotulo,
        controller: _obsRebanhoController,
        altura: null,
        linhas: 3,
        dica: 'Comentar problemas do rebanho',
        textCapitalization: TextCapitalization.sentences,
      ),
    ]),
  ];

  /// Seção 1 — "Atividades do Dia"  /// Seção 1 — "Atividades do Dia": caixas de marcar, uma por atividade.
  List<Widget> _atividadesDoDia() => [
    for (final a in _atividades) ...[
      _atividade(a.$1, a.$2, a.$3, a.$4),
      const SizedBox(height: 8),
    ],
  ];

  Widget _atividade(
    String chave,
    String texto,
    IconData? icone,
    String? imagem,
  ) => _linhaMarcar(
    texto,
    icone,
    _atividadesMarcadas.contains(chave),
    (v) => _marcarAtividade(chave, v),
    imagem: imagem,
  );

  /// Linha com caixa de marcar, ícone azul e texto (Atividades do Dia,
  /// Sanidade Animal...): marcada fica com fundo azul claro e borda azul.
  Widget _linhaMarcar(
    String texto,
    IconData? icone,
    bool marcada,
    ValueChanged<bool> aoMarcar, {
    String? imagem,
    // botão: sem a caixa de marcar
    bool semCaixa = false,
    // travado: cinza e sem resposta ao toque
    bool habilitado = true,
  }) {
    const azulIcone = Color(0xFF228cb9);
    return Opacity(
      opacity: habilitado ? 1 : 0.4,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: habilitado ? () => aoMarcar(!marcada) : null,
        child: Container(
          // 54 no mínimo; cresce quando o texto ocupa mais linhas
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.only(left: 4, right: 12),
          decoration: BoxDecoration(
            color: marcada ? const Color(0xFFE3F2FD) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: marcada ? _azulBotao : const Color(0xFFCFD8DC),
            ),
          ),
          child: Row(
            children: [
              if (semCaixa)
                const SizedBox(width: 14)
              else
                Checkbox(
                  value: marcada,
                  activeColor: _azulBotao,
                  // quadrado com a borda fina
                  side: const BorderSide(width: 1.2, color: Color(0xFF90A4AE)),
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) => aoMarcar(v ?? false),
                ),
              if (imagem != null)
                Image.asset(
                  'assets/images/$imagem',
                  width: 24,
                  height: 24,
                  color: azulIcone,
                )
              else
                Icon(icone, size: 24, color: azulIcone),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  texto,
                  // mesmo peso das opções da Seção 2
                  style: _textoGrosso(_corRotulo).copyWith(fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Seção 1 — Identificação.
  List<Widget> _secaoIdentificacao() => [
    CampoValorTopo(
      rotulo: '* Data do Registro',
      corRotulo: _corRotulo,
      valor: _formatar(_data),
      icone: Icon(Icons.calendar_month, color: _corRotulo, size: 20),
      onTap: _escolherData,
    ),
    const SizedBox(height: 10),
    SeletorCampoWidget<String>(
      rotulo: '* Fazenda',
      corRotulo: _corRotulo,
      valor: _fazenda,
      opcoes: _fazendas,
      destaque: true,
      onChanged: (v) => setState(() => _fazenda = v),
    ),
    const SizedBox(height: 10),
    // o usuário logado, sem digitar
    CampoValorTopo(
      rotulo: 'Responsável (quem fez o resumo)',
      corRotulo: _corRotulo,
      valor: _responsavel,
    ),
  ];
}
