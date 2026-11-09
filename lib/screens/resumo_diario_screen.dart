import 'dart:async';
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
import 'chuva_screen.dart';
import 'mapa_screen.dart';
import 'tratamento_modal.dart';
import '../widgets/indicador_conectividade_widget.dart';

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

  static const _totalSecoes = 11;

  /// 0 = tela inicial (escolha da fazenda), antes das seções.
  int _secao = 0;

  // Seção 3 — Conferência de Rebanho
  String? _conferiuGado; // 'todo', 'parte', 'nao'
  final _encontradosController = TextEditingController();
  String? _conferiuPrenhas; // 'sim', 'nao'
  final _obsRebanhoController = TextEditingController();
  final _obsRebanhoFoco = FocusNode();

  /// Rolagem da parte de baixo das seções (para levar a Observação da
  /// Seção 3 para cima do teclado).
  final _rolagem = ScrollController();

  // Seção 4 — Sanidade Animal: "Adicionar Tratamento" ou "Nenhum animal
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

  // Seção 6 — Atividades no Curral: "Teve atividade no curral hoje?"; com
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

  // Seção 5 — Vacinas, Vermífugos e Carrapaticidas: "Adicionar Aplicação"
  // ou "Nenhuma aplicação de vacina ou vermífugo hoje" (como a Seção 4).
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

  // pastos conferidos (Parte do Gado)
  final Set<int> _pastosConferidos = {};

  /// Animais ativos da fazenda (do servidor, ao entrar na Seção 3): o total
  /// e por pasto. null = ainda não consultado ou falhou.
  int? _animaisFazenda;
  int? _vacasPrenhas;
  Map<int, int> _animaisPorPasto = {};
  bool _carregandoAnimais = false;

  /// Animais Esperados: Gado Todo = todos os ativos da fazenda; Parte do
  /// Gado = soma dos pastos conferidos (null enquanto não escolher nenhum).
  int? get _esperados {
    if (_animaisFazenda == null) return null;
    if (_conferiuGado == 'todo') return _animaisFazenda;
    if (_pastosConferidos.isEmpty) return null;
    return _pastosConferidos.fold<int>(
      0,
      (s, id) => s + (_animaisPorPasto[id] ?? 0),
    );
  }

  /// Ao entrar na Seção 3: consulta no servidor os animais ativos da
  /// fazenda (só online; sem internet ou se falhar, avisa) e carrega os
  /// pastos guardados no aparelho para os selects.
  Future<void> _carregarAnimais() async {
    final fazenda = _fazenda;
    final bd = _bd;
    unawaited(_carregarPastos());
    if (fazenda == null || bd == null || _carregandoAnimais) return;
    setState(() => _carregandoAnimais = true);
    // checagem da internet na hora (o Resumo Diário só funciona online)
    final nivel = await ConnectivityService.instance.verificarAgora();
    String? erro = _mensagemSemInternet(nivel);
    ({int total, int prenhas, Map<int, int> porPasto})? r;
    if (erro == null) {
      r = await ResumoDiarioService.instance.animaisDaFazenda(bd, fazenda);
      if (r == null) {
        erro =
            'Não foi possível consultar os animais da fazenda. Tente '
            'novamente.';
      }
    }
    if (!mounted) return;
    setState(() {
      _carregandoAnimais = false;
      if (r != null && fazenda == _fazenda) {
        _animaisFazenda = r.total;
        _animaisPorPasto = r.porPasto;
        _vacasPrenhas = r.prenhas;
        if (!_temPrenhas) _conferiuPrenhas = null;
        if ((_diferenca ?? 0) == 0) _pastosDiferenca.clear();
      }
    });
    if (erro != null) await AppAlert.erro(context, erro);
  }

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
      bool fora(int id) => !_pastosFazenda.any((p) => p.key == id);
      _pastosDiferenca.removeWhere(fora);
      _pastosConferidos.removeWhere(fora);
    });
  }

  /// Lista para marcar um ou vários pastos ([titulo] no alto), guardados
  /// em [escolhidos] ("Quais pastos foram conferidos?" e "Em qual(is)
  /// pasto(s) está a diferença?").
  Future<void> _escolherPastos(String titulo, Set<int> escolhidos) async {
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
    final marcados = {...escolhidos};
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
            title: Text(
              titulo,
              style: const TextStyle(fontSize: 16, color: _azul),
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
      setState(() {
        escolhidos
          ..clear()
          ..addAll(marcados);
        // desmarcou todos os pastos conferidos: o Encontrados some e é limpo
        if (identical(escolhidos, _pastosConferidos) && escolhidos.isEmpty) {
          _encontradosController.clear();
        }
        // mudou o total esperado: sem diferença, limpa os pastos dela
        if ((_diferenca ?? 0) == 0) _pastosDiferenca.clear();
      });
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
  String _nomesPastos(Set<int> marcados) => [
    for (final p in _pastosFazenda)
      if (marcados.contains(p.key)) p.value,
  ].join(', ');

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _encontradosController.dispose();
    _obsRebanhoController.dispose();
    _obsRebanhoFoco.dispose();
    _rolagem.dispose();
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

  /// Nome do usuário logado como veio do login (saudação da tela inicial).
  String _nomeUsuario = '';
  String? _bd;

  /// Atividades diárias da fazenda, ligadas aos programas do app (Chuva,
  /// Mapa de Gado, Nascimento, Morte...). As já registradas no sistema no
  /// dia vão para a Seção 1; as outras, para a Seção 2 (marcar como NÃO).
  static const _atividades = <(String, String, IconData?, String?)>[
    ('choveu', 'Chuva', Icons.water_drop_outlined, null),
    ('mudei_pasto', 'Mudei o Gado de Pasto', Icons.swap_horiz, null),
    ('nutricao', 'Nutrição', Icons.grass, null),
    ('nascimento', 'Nascimento', Icons.child_care, null),
    ('aborto_natimorto', 'Aborto/Natimorto', Icons.warning_amber_rounded, null),
    ('morte', 'Morte', Icons.heart_broken_outlined, null),
  ];
  final Set<String> _atividadesMarcadas = {};

  /// Atividades já registradas no sistema para a fazenda e a data do resumo
  /// (chave -> texto antes + valor em negrito + texto depois): a Seção 1 só
  /// mostra estas.
  Map<String, (String, String, String)> _atividadesRegistradas = {};

  /// Fazenda + data das atividades carregadas (trocou, as marcações não
  /// valem mais).
  String? _chaveAtividades;
  bool _carregandoAtividades = false;

  /// Quantidade no singular ou no plural: (1, 'Bezerro nasceu',
  /// 'Bezerros nasceram') -> ' Bezerro nasceu' (o número vai à parte, em
  /// negrito).
  static String _plural(int n, String um, String varios) =>
      n == 1 ? ' $um' : ' $varios';

  /// 30 -> "30"; 12.5 -> "12,5".
  static String _mm(double v) => v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toString().replaceAll('.', ',');

  /// Botão Sim da tela inicial: consulta no servidor as atividades
  /// registradas no dia (só online) e abre a Seção 1. Sem internet ou se
  /// falhar, avisa e fica na tela inicial.
  ///
  /// [naSecao2]: volta dos programas abertos pelos links da Seção 2 — relê
  /// as atividades e fica na Seção 2, com o texto refeito.
  Future<void> _abrirSecao1({bool naSecao2 = false}) async {
    final bd = _bd;
    final fazenda = _fazenda;
    if (bd == null || fazenda == null || _carregandoAtividades) return;
    final data = _data;
    setState(() => _carregandoAtividades = true);
    // checagem da internet na hora (o Resumo Diário só funciona online)
    final nivel = await ConnectivityService.instance.verificarAgora();
    String? erro = _mensagemSemInternet(nivel);
    AtividadesDoDia? r;
    if (erro == null) {
      r = await ResumoDiarioService.instance.atividadesDoDia(bd, fazenda, data);
      if (r == null) {
        erro =
            'Não foi possível consultar as atividades do dia. Tente '
            'novamente.';
      }
    }
    if (!mounted) return;
    setState(() => _carregandoAtividades = false);
    if (erro != null) {
      await AppAlert.erro(context, erro);
      return;
    }
    // trocou a fazenda ou a data enquanto consultava: não entra
    if (fazenda != _fazenda || data != _data) return;
    final a = r!;
    final chuva = a.chuvaMm;
    final chave = '$fazenda|${_formatar(data)}';
    setState(() {
      if (chave != _chaveAtividades) {
        _atividadesMarcadas.clear();
      }
      _chaveAtividades = chave;
      _atividadesRegistradas = {
        if (chuva != null) 'choveu': ('Choveu ', '${_mm(chuva)} mm', ''),
        // sem valor em negrito
        if (a.mudouPasto) 'mudei_pasto': ('Trocamos animais de pasto', '', ''),
        if (a.nutricao)
          'nutricao': ('Distribuímos Nutrição nos Cochos', '', ''),
        // quantidade em negrito na frente, singular ou plural
        if (a.nascimentos > 0)
          'nascimento': (
            '',
            '${a.nascimentos}',
            _plural(a.nascimentos, 'Bezerro nasceu', 'Bezerros nasceram'),
          ),
        if (a.abortos > 0)
          'aborto_natimorto': (
            '',
            '${a.abortos}',
            _plural(
              a.abortos,
              'Animal Abortou/Natimorto',
              'Animais Abortaram/Natimorto',
            ),
          ),
        if (a.mortes > 0)
          'morte': (
            '',
            '${a.mortes}',
            _plural(a.mortes, 'Animal morreu', 'Animais morreram'),
          ),
      };
      _atividadesMarcadas.removeWhere(
        (a) => !_atividadesRegistradas.containsKey(a),
      );
      // o texto da Seção 2 pode ter mudado: confirma de novo
      _secao2Confirmada = false;
      // voltando dos links: fica na Seção 2, a não ser que ela tenha ficado
      // sem nenhuma afirmativa e a Seção 1 ganhou atividade para marcar
      _secao = naSecao2 && (_chavesNaoRegistradas.isNotEmpty || _secao1Completa)
          ? 2
          : 1;
    });
  }

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
    // entrou ou saiu da Observação: mostra ou esconde a barra Anterior/Próximo
    _obsRebanhoFoco.addListener(() {
      if (mounted) setState(() {});
    });
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

  /// Confere a data da tela. Com [nova] (data escolhida no calendário),
  /// confere ela antes de aceitar: dia que já tem resumo ou folga avisa e
  /// não troca a data.
  Future<void> _conferirDiaAnterior({DateTime? nova}) async {
    final bd = _bd;
    final fazenda = _fazenda;
    if (!mounted || bd == null || fazenda == null) return;
    final minha = ++_conferencia;
    final data = nova ?? _data;
    setState(() {
      _conferindoDia = true;
      _diaPendente = false;
      _erroConferencia = null;
    });
    // checagem da internet na hora (o Resumo Diário só funciona online)
    final nivel = await ConnectivityService.instance.verificarAgora();
    ({bool pendente, String? tipoNoDia})? r;
    String? erro = _mensagemSemInternet(nivel);
    if (erro == null) {
      r = await ResumoDiarioService.instance.diaAnteriorPendente(
        bd,
        fazenda,
        data,
      );
      if (r == null) {
        erro =
            'Não foi possível conferir os resumos anteriores. Tente '
            'novamente.';
      }
    }
    if (!mounted || minha != _conferencia) return;
    // dia escolhido no calendário já registrado: avisa, fica na data que
    // estava e confere ela de novo
    final tipo = r?.tipoNoDia;
    if (nova != null && tipo != null) {
      setState(() => _conferindoDia = false);
      await AppAlert.erro(
        context,
        tipo == 'F'
            ? 'O dia ${_formatar(nova)} já foi registrado como folga. '
                  'Escolha outra data.'
            : 'O dia ${_formatar(nova)} já tem o resumo registrado. '
                  'Escolha outra data.',
      );
      if (!mounted || minha != _conferencia) return;
      await _conferirDiaAnterior();
      return;
    }
    setState(() {
      if (nova != null && erro == null) _data = nova;
      _conferindoDia = false;
      // só o dia de hoje cobra o dia anterior: no resumo de um dia passado
      // (ex.: depois do "Registrar" do aviso) não cobra o dia antes dele, senão
      // voltaria um dia por vez sem fim
      _diaPendente = r?.pendente == true && DateUtils.isSameDay(data, _hoje());
      _erroConferencia = erro;
    });
    // Dia anterior sem resumo: avisa num modal (só com o Resumo na tela).
    // "Registrar" passa a tela para esse dia (o usuário continua o
    // resumo dele); "Dia de Folga" grava o dia como Folga e volta para
    // hoje.
    if (_diaPendente && TickerMode.of(context)) {
      final dia = data.subtract(const Duration(days: 1));
      final escolha = await _avisoDiaSemResumo(
        'Não foi registrado o resumo do dia ${_formatar(dia)}.',
      );
      if (!mounted || minha != _conferencia) return;
      if (escolha == 'resumo') {
        setState(() => _data = dia);
        await _conferirDiaAnterior();
      } else if (escolha == 'folga') {
        await _registrarFolga(dia);
      }
    }
  }

  bool _registrandoFolga = false;

  /// Grava o [dia] como Folga da fazenda (no servidor, só online) e volta
  /// a tela para hoje. Se não conseguir, avisa e confere de novo.
  Future<void> _registrarFolga(DateTime dia) async {
    final bd = _bd;
    final fazenda = _fazenda;
    if (bd == null || fazenda == null) return;
    setState(() => _registrandoFolga = true);
    // checagem da internet na hora (gravação no servidor)
    final nivel = await ConnectivityService.instance.verificarAgora();
    String? erro = _mensagemSemInternet(nivel);
    erro ??= await ResumoDiarioService.instance.registrarFolga(
      bd,
      fazenda,
      _nomeUsuario,
      dia,
    );
    if (!mounted) return;
    setState(() => _registrandoFolga = false);
    if (erro != null) {
      await AppAlert.erro(context, erro);
      if (!mounted) return;
    } else {
      await AppAlert.sucesso(
        context,
        'Folga do dia ${_formatar(dia)} registrada com sucesso.',
      );
      if (!mounted) return;
      setState(() => _data = _hoje());
    }
    await _conferirDiaAnterior();
  }

  /// Texto do aviso quando a internet não está boa (null = internet ok).
  static String? _mensagemSemInternet(NivelConexao nivel) => switch (nivel) {
    NivelConexao.semInternet =>
      'Sem internet! O Resumo Diário só pode ser feito com o aplicativo '
          'online. Conecte-se à internet e tente novamente.',
    NivelConexao.internetRuim =>
      'Internet ruim ou intermitente! O Resumo Diário só pode ser feito '
          'com o aplicativo online. Tente novamente quando a internet estiver '
          'estável.',
    _ => null,
  };

  /// Modal do dia sem resumo: mesmo vermelho e branco do alerta de erro da
  /// Pesagem (pesagem_itens_screen.dart) e ícone de atenção. Devolve
  /// 'resumo' (Registrar) ou 'folga' (Dia de Folga). Feito aqui
  /// para não mexer no AppAlert, que é usado pelos outros programas.
  Future<String?> _avisoDiaSemResumo(String mensagem) {
    final fundo = Colors.red[900]!.withValues(alpha: 0.95);
    const texto = Colors.white;
    FocusManager.instance.primaryFocus?.unfocus();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: fundo,
        // sem o tom que o Material 3 põe por cima: o vermelho fica igual
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        // modal mais largo que o padrão, para os dois links caberem numa
        // linha só
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: texto, size: 30),
            const SizedBox(width: 10),
            Text('Atenção', style: EstiloApp.negrito(18, texto)),
          ],
        ),
        // largura toda que o modal permite (senão ele encolhe no texto)
        content: SizedBox(
          width: double.maxFinite,
          child: Text(
            mensagem,
            style: const TextStyle(fontSize: 16, color: texto),
          ),
        ),
        // dois links lado a lado no lugar do OK: "Registrar" (faz o resumo
        // do dia) com o destaque que o OK tinha; "Dia de Folga" mais claro,
        // sem negrito
        actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'resumo'),
                child: Text('Registrar', style: EstiloApp.negrito(14, texto)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'folga'),
                child: Text(
                  'Dia de Folga',
                  style: TextStyle(
                    fontSize: 14,
                    color: texto.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
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
    // a data só muda se o dia escolhido ainda não tem resumo nem folga
    await _conferirDiaAnterior(nova: d);
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
            onPressed: _conferindoDia || _registrandoFolga
                ? null
                : () => _escolherDataInicial(),
          ),
        ],
      ),
    ),
    if (_conferindoDia || _registrandoFolga)
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              _registrandoFolga
                  ? 'Registrando a folga...'
                  : 'Conferindo os resumos anteriores...',
              style: const TextStyle(color: Colors.grey),
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

  /// Pergunta da tela inicial: Sim (btn-primary) vai para a Seção 1; Não
  /// (btn-default) sai para a Home.
  List<Widget> _perguntaAtualizacao() => [
    Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 17, color: EstiloApp.azulBarra),
          children: [
            const TextSpan(text: 'Todos os usuários já '),
            TextSpan(
              text: 'Atualizaram',
              style: EstiloApp.negrito(17, EstiloApp.azulBarra),
            ),
            const TextSpan(text: ' os dados On-Line?'),
          ],
        ),
      ),
    ),
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: EstiloApp.azulPrimario,
                  disabledBackgroundColor: EstiloApp.azulPrimario,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _carregandoAtividades ? null : _abrirSecao1,
                child: _carregandoAtividades
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Sim', style: TextStyle(fontSize: 16)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton(
                // mesmo btn-default do Anterior das seções
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE9ECEF),
                  foregroundColor: const Color(0xFF333333),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _carregandoAtividades ? null : _voltar,
                child: const Text('Não', style: TextStyle(fontSize: 16)),
              ),
            ),
          ),
        ],
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
      await _iniciarFazenda(escolhida);
    }
  }

  /// Fazenda escolhida ou trocada: recomeça do zero para ela, com a data de
  /// hoje e a conferência dos resumos no servidor.
  Future<void> _iniciarFazenda(String id) async {
    setState(() {
      _fazenda = id;
      _data = _hoje();
    });
    await _conferirDiaAnterior();
  }

  /// Fazenda escolhida no select da tela inicial: confere o dia anterior
  /// dela.
  void _selecionarFazenda(String? id) {
    if (id != null) _iniciarFazenda(id);
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
      // só com a data já conferida e válida para fazer o resumo
      if (_fazenda != null &&
          !_conferindoDia &&
          !_registrandoFolga &&
          !_diaPendente &&
          _erroConferencia == null)
        ..._perguntaAtualizacao(),
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

  /// Só avança com a seção atual preenchida. Os dados de cada seção ficam
  /// guardados ao ir e voltar.
  Future<void> _proximo() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_secao == 2) {
      if (!_secao2Completa) return;
      setState(() => _secao = 3);
      // "Animais Esperados" da Seção 3 (sempre atualizado ao entrar)
      await _carregarAnimais();
      return;
    }
    if (_secao == 3) {
      if (_animaisFazenda == null) {
        // não conseguiu consultar os animais (esperados e prenhas): de novo
        await _carregarAnimais();
        return;
      }
      if (_conferiuGado == null) {
        await AppAlert.erro(context, 'Informe se conferiu o gado.');
        return;
      }
      if (_conferiuGado == 'parte' && _pastosConferidos.isEmpty) {
        await AppAlert.erro(context, 'Informe quais pastos foram conferidos.');
        return;
      }
      if (_conferiuGado != 'nao') {
        if (_encontradosController.text.trim().isEmpty) {
          await AppAlert.erro(
            context,
            'Informe o Total de Animais Encontrados.',
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
      if (_temPrenhas && _conferiuPrenhas == null) {
        await AppAlert.erro(context, 'Informe se conferiu as vacas prenhas.');
        return;
      }
      setState(() => _secao = 4);
      return;
    }
    if (_secao == 4) {
      if (!_nenhumDoente && _tratamentos.isEmpty) {
        await AppAlert.erro(
          context,
          'Adicione um tratamento ou marque "Nenhum animal doente ou '
          'medicado hoje".',
        );
        return;
      }
      setState(() => _secao = 5);
      return;
    }
    if (_secao == 5) {
      if (!_nenhumaAplicacao && _aplicacoes.isEmpty) {
        await AppAlert.erro(
          context,
          'Adicione uma aplicação ou marque "Nenhuma aplicação de vacina ou '
          'vermífugo hoje".',
        );
        return;
      }
      setState(() => _secao = 6);
      return;
    }
    if (_secao == 6) {
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
      // A Seção 7 vem nas próximas etapas.
      return;
    }
    if (_secao == 1) {
      if (_fazenda == null) {
        await AppAlert.erro(context, 'Selecione a Fazenda.');
        return;
      }
      // o Próximo fica inativo até confirmar as atividades (ver
      // [_secao1Completa])
      if (!_secao1Completa) return;
      setState(() {
        _secao = 2;
        // toda vez que entra na Seção 2 confirma de novo
        _secao2Confirmada = false;
      });
    }
  }

  void _anterior() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_secao > 1) {
      setState(() {
        _secao--;
        // voltou para a Seção 2: confirma de novo
        if (_secao == 2) _secao2Confirmada = false;
      });
    }
  }

  /// Seção 1 pronta para o Próximo: sem atividade registrada no dia, ou com
  /// todas as atividades marcadas (tocadas).
  bool get _secao1Completa =>
      _atividadesRegistradas.keys.every(_atividadesMarcadas.contains);

  /// Seção 2: o Sim do "Você Confirma todas as afirmativas acima?" foi
  /// tocado com a Seção 1 toda marcada.
  bool _secao2Confirmada = false;

  /// Seção 2 pronta para o Próximo: Seção 1 toda marcada e confirmada no
  /// Sim (ou sem nenhuma atividade sem registro, sem afirmativa para
  /// confirmar).
  bool get _secao2Completa =>
      _secao1Completa && (_secao2Confirmada || _chavesNaoRegistradas.isEmpty);

  void _marcarAtividade(String chave, bool marcada) {
    setState(() {
      if (marcada) {
        _atividadesMarcadas.add(chave);
      } else {
        _atividadesMarcadas.remove(chave);
      }
    });
  }

  /// Chaves das atividades sem registro no dia (as da Seção 2).
  Iterable<String> get _chavesNaoRegistradas => _atividades
      .map((a) => a.$1)
      .where((c) => !_atividadesRegistradas.containsKey(c));

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
      backgroundColor: _fundoTela,
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
                        controller: _rolagem,
                        // espaço no fim para o último item passar do botão Próximo
                        // (que fica por cima, junto com a barra do celular)
                        padding: EdgeInsets.fromLTRB(
                          12,
                          0,
                          12,
                          _barraVisivel
                              ? 96 + MediaQuery.of(context).padding.bottom
                              : 16,
                        ),
                        children: _rolavelDaSecao(),
                      ),
                      // Próximo sempre visível; a tela rola por trás dele. Com o
                      // teclado aberto ele sai da frente, para não cobrir o campo
                      // que está sendo digitado — menos na Seção 3, onde fica
                      // acima do teclado (a Observação é o último campo).
                      if (_barraVisivel)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: SafeArea(
                            top: false,
                            // o fundo da barra vai até embaixo (atrás da barra do
                            // celular), para a lista não aparecer ali
                            bottom: false,
                            child: Container(
                              padding: EdgeInsets.fromLTRB(
                                12,
                                10,
                                12,
                                12 + MediaQuery.of(context).padding.bottom,
                              ),
                              // sem a sombra em cima: fica junto com a tela
                              color: _fundoTela,
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
                                          // inativo: o mesmo azul, clareado
                                          disabledBackgroundColor: _azulBotao
                                              .withValues(alpha: 0.35),
                                          disabledForegroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                        // Seção 1: inativo até confirmar as
                                        // atividades registradas; Seção 2: até o Sim da
                                        // confirmação
                                        onPressed:
                                            (_secao == 1 && !_secao1Completa) ||
                                                (_secao == 2 &&
                                                    !_secao2Completa)
                                            ? null
                                            : _proximo,
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

  /// Azul claro da tarja (azul a 10% sobre o branco). Na Seção 1 (em teste)
  /// é também o fundo da tela toda.
  static final _azulTarja = Color.alphaBlend(
    Colors.blue.withValues(alpha: 0.1),
    Colors.white,
  );

  /// Fundo da tela e da barra do Próximo: azul da tarja nas Seções 1 a 3 (em
  /// teste), branco na tela inicial e nas outras.
  Color get _fundoTela =>
      _secao >= 1 && _secao <= 3 ? _azulTarja : Colors.white;

  /// Tarja de todas as seções: fazenda, data, barra de progresso e "Seção X
  /// de 11", de ponta a ponta, sem bordas arredondadas.
  Widget _progresso() {
    return Container(
      width: double.infinity,
      color: _azulTarja,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: _conteudoProgresso(),
    );
  }

  Widget _conteudoProgresso() {
    return Column(
      children: [
        // primeiro a fazenda e a data do resumo
        Row(
          children: [
            Expanded(
              child: Text(
                _nomeFazenda,
                style: const TextStyle(fontSize: 13, color: Colors.blue),
              ),
            ),
            const SizedBox(width: 10),
            Text(_formatar(_data), style: EstiloApp.negrito(13, Colors.blue)),
          ],
        ),
        const SizedBox(height: 8),
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
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Seção $_secao de $_totalSecoes',
            style: const TextStyle(fontSize: 13, color: Colors.blue),
          ),
        ),
      ],
    );
  }

  // negrito/tamanho: o título em negrito e maior (ex.: Seções 1 e 2).
  Widget _tituloAzul(
    String texto, {
    bool negrito = false,
    double tamanho = 15,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
    child: Text(
      texto,
      textAlign: TextAlign.center,
      style: negrito
          ? EstiloApp.negrito(tamanho, Colors.blue[300]!)
          : TextStyle(
              fontSize: tamanho,
              fontWeight: FontWeight.bold,
              color: Colors.blue[300],
            ),
    ),
  );

  /// Parte fixa de cada seção (não rola).
  List<Widget> _fixoDaSecao() => switch (_secao) {
    2 => [
      // mesmo título da Seção 1 (maior e em negrito)
      _tituloAzul('Atividades NÃO Registradas', tamanho: 17),
      const SizedBox(height: 16),
    ],
    // mesmo tamanho do título da Seção 2
    3 => [_tituloAzul('Contagem de Animais Hoje', tamanho: 17)],
    4 => [_tituloAzul('Tratamentos Realizados Hoje')],
    5 => [_tituloAzul('Aplicações Realizadas Hoje')],
    6 => [_tituloAzul('O Que Foi Feito Hoje')],
    _ => [
      _tituloAzul('Atividades Registradas', tamanho: 17),
      if (_atividadesRegistradas.isNotEmpty)
        Padding(
          // mesmo espaço depois do título da Seção 2; alinhado aos cards
          padding: const EdgeInsets.only(left: 10, top: 16, bottom: 10),
          child: Text(
            _atividadesRegistradas.length == 1
                ? 'Clique na Atividade para Confirmar!'
                : 'Clique nas Atividades para Confirmar!',
            style: EstiloApp.negrito(14, _corRotulo),
          ),
        ),
    ],
  };

  /// Campos e selects da Seção 3 direto no fundo azul, sem o painel cinza.
  Widget _semPainel(List<Widget> filhos) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: filhos);

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
    2 => _atividadesNaoRegistradas(),
    3 => _conferenciaRebanho(),
    4 => [
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
    5 => [
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
    6 => _atividadesNoCurral(),
    _ => const [],
  };

  // ---------------------------------------------------------------------
  // Seção 6 — Atividades no Curral
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
  // Seção 3 — Conferência de Rebanho
  // ---------------------------------------------------------------------

  // negrito: o negrito forte do app (ex.: Seção 3); espacoAntes: espaço
  // acima da pergunta
  Widget _pergunta(
    String texto, {
    bool negrito = false,
    double espacoAntes = 14,
  }) => Padding(
    padding: EdgeInsets.fromLTRB(2, espacoAntes, 2, 8),
    child: Text(
      texto,
      style: negrito
          ? EstiloApp.negrito(15, const Color(0xFF455A64))
          : const TextStyle(
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
  /// azul. Ícone azul no centro e o texto embaixo. [semBorda]: como os cards
  /// da Seção 1 — sem contorno, azul bem claro e, escolhida, azul mais escuro.
  Widget _opcoes(
    List<(String, String, IconData)> opcoes,
    String? escolhida,
    ValueChanged<String> aoEscolher, {
    bool semBorda = false,
  }) {
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
                      ? (semBorda
                            ? const Color(0xFFCFE5FA)
                            : const Color(0xFFE3F2FD))
                      : (semBorda ? const Color(0xFFF9FCFF) : Colors.white),
                  borderRadius: BorderRadius.circular(8),
                  border: semBorda
                      ? null
                      : Border.all(
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

  /// "9999 Animais Esperados" (número em negrito, do tamanho do mm da
  /// chuva): Gado Todo = ativos da fazenda; Parte do Gado = os dos pastos
  /// conferidos. Consultando ou sem pastos escolhidos, avisa.
  Widget _animaisEsperados() {
    final esperados = _esperados;
    final texto = TextStyle(fontSize: 15, color: _corRotulo);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: esperados == null
          ? Text(
              _carregandoAnimais
                  ? 'Consultando os animais da fazenda...'
                  : _animaisFazenda == null
                  ? 'Não foi possível consultar os animais da fazenda.'
                  : 'Escolha os pastos conferidos.',
              style: texto.copyWith(fontStyle: FontStyle.italic),
            )
          : Text.rich(
              TextSpan(
                style: texto,
                children: [
                  TextSpan(
                    text: '$esperados',
                    style: _textoGrosso(_corRotulo).copyWith(fontSize: 14),
                  ),
                  TextSpan(
                    text: esperados == 1
                        ? ' Animal Esperado'
                        : ' Animais Esperados',
                  ),
                ],
              ),
            ),
    );
  }

  /// Select de pastos da Seção 3 (abre [_escolherPastos]) e, embaixo, os
  /// nomes dos escolhidos.
  List<Widget> _seletorPastos(String rotulo, Set<int> escolhidos) => [
    CampoValorTopo(
      rotulo: rotulo,
      corRotulo: _corRotulo,
      valor: escolhidos.isEmpty
          ? ''
          : '${escolhidos.length} pasto(s) selecionado(s)',
      icone: Icon(Icons.arrow_drop_down, color: _corRotulo),
      onTap: () => _escolherPastos(rotulo.replaceFirst('* ', ''), escolhidos),
    ),
    if (escolhidos.isNotEmpty)
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
        child: Text(
          _nomesPastos(escolhidos),
          style: TextStyle(
            fontSize: 13,
            fontStyle: FontStyle.italic,
            color: _corRotulo,
          ),
        ),
      ),
  ];

  /// Barra Anterior/Próximo na tela: some com o teclado aberto, menos na
  /// Observação Sobre o Rebanho (Seção 3) — campo não obrigatório, os botões
  /// ficam acima do teclado para seguir sem precisar fechá-lo.
  bool get _barraVisivel =>
      !_tecladoAberto || (_secao == 3 && _obsRebanhoFoco.hasFocus);

  /// A fazenda tem vacas prenhas (consultado ao entrar na Seção 3)?
  bool get _temPrenhas => (_vacasPrenhas ?? 0) > 0;

  /// A Observação Sobre o Rebanho aparece depois de responder "Conferiu o
  /// Gado?" e, se a fazenda tem vacas prenhas, "Conferiu as Vacas Prenhas?".
  bool get _obsRebanhoVisivel =>
      _vacasPrenhas != null &&
      _conferiuGado != null &&
      (!_temPrenhas || _conferiuPrenhas != null);

  /// Resposta de uma das perguntas da Seção 3. Se com ela a Observação
  /// aparece, o cursor vai para ela (teclado aberto) e a tela rola até o
  /// fim, deixando a Observação, o teclado e os botões Anterior/Próximo
  /// visíveis.
  void _responderRebanho(VoidCallback mudar) {
    final antes = _obsRebanhoVisivel;
    setState(mudar);
    if (antes || !_obsRebanhoVisivel) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _obsRebanhoFoco.requestFocus();
      // o teclado demora a abrir (e a tela encolhe aos poucos): rola até o
      // fim algumas vezes, até ele terminar de abrir
      for (final ms in const [350, 700, 1100]) {
        Future.delayed(Duration(milliseconds: ms), () {
          if (!mounted || !_rolagem.hasClients) return;
          _rolagem.animateTo(
            _rolagem.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        });
      }
    });
  }

  List<Widget> _conferenciaRebanho() => [
    _pergunta('Conferiu o Gado?', negrito: true),
    _opcoes(
      const [
        ('todo', 'Gado Todo', Icons.done_all),
        ('parte', 'Parte do Gado', Icons.rule),
        ('nao', 'Não Conferi', Icons.block),
      ],
      _conferiuGado,
      (v) => _responderRebanho(() {
        // toda troca entre Gado Todo, Parte do Gado e Não Conferi começa
        // do zero: limpa os campos e os selects da opção anterior
        if (v != _conferiuGado) {
          _encontradosController.clear();
          _pastosConferidos.clear();
          _pastosDiferenca.clear();
        }
        _conferiuGado = v;
      }),
      semBorda: true,
    ),
    // os totais só com "Gado Todo" ou "Parte do Gado"
    if (_conferiuGado == 'todo' || _conferiuGado == 'parte') ...[
      const SizedBox(height: 10),
      _semPainel([
        // Parte do Gado: primeiro os pastos conferidos
        if (_conferiuGado == 'parte') ...[
          ..._seletorPastos(
            '* Quais pastos foram conferidos?',
            _pastosConferidos,
          ),
          const SizedBox(height: 10),
        ],
        // Esperados, Encontrados e a diferença: no Gado Todo direto; na Parte
        // do Gado, depois de escolher os pastos conferidos
        if (_conferiuGado == 'todo' || _pastosConferidos.isNotEmpty) ...[
          _animaisEsperados(),
          const SizedBox(height: 10),
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
            ..._seletorPastos(
              '* Em qual(is) pasto(s) está a diferença?',
              _pastosDiferenca,
            ),
          ],
        ],
      ]),
    ],
    // só quando a fazenda tem vacas prenhas (Positivas e ainda sem
    // nascimento, aborto, natimorto ou absorção)
    if (_temPrenhas) ...[
      // mais espaço antes desta pergunta
      _pergunta('Conferiu as Vacas Prenhas?', negrito: true, espacoAntes: 26),
      _opcoes(
        const [
          ('sim', 'Sim', Icons.check_circle_outline),
          ('nao', 'Não', Icons.highlight_off),
        ],
        _conferiuPrenhas,
        (v) => _responderRebanho(() => _conferiuPrenhas = v),
        semBorda: true,
      ),
    ],
    // a Observação só depois de responder as perguntas acima
    if (_obsRebanhoVisivel) ...[
      const SizedBox(height: 14),
      _semPainel([
        CampoTextoTopo(
          rotulo: 'Observação Sobre o Rebanho',
          corRotulo: _corRotulo,
          controller: _obsRebanhoController,
          focusNode: _obsRebanhoFoco,
          altura: null,
          linhas: 2,
          dica: 'Comentar problemas do rebanho',
          textCapitalization: TextCapitalization.sentences,
        ),
      ]),
    ],
  ];

  /// Seção 1 — "Atividades Registradas": uma linha por atividade registrada
  /// no dia, em cards com ícone (ver [_atividade]). Tocar no card
  /// marca (azul mais forte e check verde); tocar de novo desmarca.
  List<Widget> _atividadesDoDia() => [
    if (_atividadesRegistradas.isEmpty)
      Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Text(
          'Nenhuma Atividade',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: _corRotulo),
        ),
      ),
    // só as já registradas no sistema
    for (final a in _atividades)
      if (_atividadesRegistradas[a.$1] case final linha?) ...[
        _atividade(a.$1, linha.$1, linha.$2, linha.$3, a.$3, a.$4),
        const SizedBox(height: 8),
      ],
  ];

  /// Seção 2: como cada atividade sem registro no dia aparece na conversa
  /// (texto normal + a palavra que vira link para o programa).
  static const _frasesNaoRegistradas = <String, (String, String)>{
    'choveu': ('não ', 'Choveu'),
    'mudei_pasto': ('os animais estão nos mesmos ', 'Pastos'),
    'nutricao': ('ninguém distribuiu ', 'Nutrição'),
    'nascimento': ('não houve ', 'Nascimentos'),
    'aborto_natimorto': ('nenhum animal ', 'Abortou/Natimorto'),
    'morte': ('nenhum animal ', 'Morreu'),
  };

  /// Seção 2 — "Atividades NÃO Registradas": uma conversa com o usuário
  /// logado contando o que não tem registro da fazenda no dia, ex.:
  /// "Reinaldo! Hoje não Choveu, os animais estão nos mesmos Pastos, ...",
  /// direto no fundo azul (sem card). As palavras de cada atividade aparecem
  /// como link (sublinhado) para o programa (ver
  /// [_abrirPrograma]). Embaixo, a confirmação com o botão Sim (ver
  /// [_confirmarSecao2]).
  List<Widget> _atividadesNaoRegistradas() {
    final chaves = _chavesNaoRegistradas.toList();
    if (chaves.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Text(
            'Todas as atividades do dia estão registradas no sistema!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: _corRotulo),
          ),
        ),
      ];
    }
    final hoje = DateUtils.isSameDay(_data, _hoje());
    // visual de link: azul padrão de link (o da internet) e sublinhado
    const azulLink = Color(0xFF0645AD);
    const link = TextStyle(
      fontSize: 17,
      color: azulLink,
      decoration: TextDecoration.underline,
      decorationColor: azulLink,
    );
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$_nomeUsuario!', style: EstiloApp.negrito(19, _corRotulo)),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 17, height: 1.5, color: _corRotulo),
                children: [
                  // dia passado: a data no lugar do "Hoje"
                  TextSpan(
                    text: hoje ? 'Hoje ' : 'No dia ${_formatar(_data)} ',
                  ),
                  for (var i = 0; i < chaves.length; i++) ...[
                    if (i > 0) const TextSpan(text: ', '),
                    TextSpan(text: _frasesNaoRegistradas[chaves[i]]!.$1),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        onTap: () => _abrirPrograma(chaves[i]),
                        child: Text(
                          _frasesNaoRegistradas[chaves[i]]!.$2,
                          style: link,
                        ),
                      ),
                    ),
                  ],
                  const TextSpan(text: '.'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Você Confirma todas as afirmativas acima?',
              style: EstiloApp.negrito(17, _corRotulo),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 140,
              height: 44,
              child: ElevatedButton(
                // branco com sombra leve até tocar; confirmado, azul com o check
                style: ElevatedButton.styleFrom(
                  backgroundColor: _secao2Confirmada
                      ? _azulBotao
                      : Colors.white,
                  foregroundColor: _secao2Confirmada
                      ? Colors.white
                      : _azulBotao,
                  elevation: _secao2Confirmada ? 0 : 2,
                  shadowColor: Colors.black.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _confirmarSecao2,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_secao2Confirmada) ...[
                      const Icon(Icons.check, size: 20),
                      const SizedBox(width: 6),
                    ],
                    const Text('Sim', style: TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  /// Link de uma atividade da Seção 2: Choveu abre o programa da Chuva (com
  /// a fazenda e a data do resumo); as outras, o Mapa de Gado (Tabuleiro)
  /// com a fazenda do resumo. Ao voltar, relê as atividades e fica na
  /// Seção 2 com o texto refeito.
  Future<void> _abrirPrograma(String chave) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (ctx) => chave == 'choveu'
            ? ChuvaScreen(
                onBack: () => Navigator.pop(ctx, false),
                fazendaInicial: _fazenda,
                dataInicial: _data,
                aoRegistrar: () => Navigator.pop(ctx, true),
              )
            : MapaScreen(
                onBack: () => Navigator.pop(ctx, false),
                fazendaInicial: _fazenda,
              ),
      ),
    );
    if (mounted) await _abrirSecao1(naSecao2: true);
  }

  /// Sim do "Você Confirma todas as afirmativas acima?": com alguma
  /// atividade da Seção 1 sem marcar (ex.: uma nova, registrada pelos
  /// links), volta para a Seção 1 (o Próximo dela fica desativado até
  /// marcar); com a Seção 1 toda marcada, ativa o Próximo da Seção 2.
  void _confirmarSecao2() {
    setState(() {
      if (_secao1Completa) {
        _secao2Confirmada = true;
      } else {
        _secao = 1;
      }
    });
  }

  /// Card de uma atividade da Seção 1: ícone, texto (o valor em negrito, com
  /// texto antes e/ou depois) e, marcado, o check verde à direita.
  Widget _atividade(
    String chave,
    String texto,
    String valor,
    String depois,
    IconData? icone,
    String? imagem,
  ) {
    final marcada = _atividadesMarcadas.contains(chave);
    // card do tamanho da informação (cada um de um tamanho, chamando a
    // atenção para o dado), à esquerda, afastado um pouco da borda da tela
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 10),
      child: _linhaMarcar(
        texto,
        icone,
        marcada,
        (v) => _marcarAtividade(chave, v),
        imagem: imagem,
        // vazio: só o texto, sem negrito (ex.: Trocamos animais de pasto)
        valor: valor,
        depois: depois,
        semCaixa: true,
        // azul bem claro; o marcado, um azul mais escuro
        fundo: const Color(0xFFF9FCFF),
        fundoMarcado: const Color(0xFFCFE5FA),
        ajustado: true,
        semBorda: true,
        // menos espaço entre a borda do card e o ícone
        recuo: 6,
        // o espaço do check fica sempre reservado: o card não muda de
        // tamanho ao marcar
        acao: SizedBox(
          width: 28,
          child: marcada
              ? Icon(Icons.check, color: Colors.green[600], size: 28)
              : null,
        ),
      ),
    );
  }

  /// Card do tamanho do conteúdo ([ajustado], Seção 1): o texto fica
  /// sempre numa linha só — se não couber, a fonte encolhe um pouco em vez
  /// de quebrar (ex.: Distribuímos Nutrição nos Cochos).
  static Widget _umaLinha(bool ajustado, Widget texto) => ajustado
      ? FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: texto,
        )
      : texto;

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
    // com valor: o texto fica sem negrito e só o valor em negrito
    String? valor,
    // texto normal depois do valor (ex.: "3" + " Bezerros nasceram")
    String depois = '',
    // botão no fim da linha, separado do texto
    Widget? acao,
    // fundo do card desmarcado e do marcado
    Color fundo = Colors.white,
    Color fundoMarcado = const Color(0xFFE3F2FD),
    // card do tamanho do conteúdo (não ocupa a largura toda)
    bool ajustado = false,
    // sem a borda (antes e depois de marcar)
    bool semBorda = false,
    // espaço à esquerda do ícone quando não tem a caixa de marcar
    double recuo = 14,
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
            color: marcada ? fundoMarcado : fundo,
            borderRadius: BorderRadius.circular(8),
            border: semBorda
                ? null
                : Border.all(
                    color: marcada ? _azulBotao : const Color(0xFFCFD8DC),
                  ),
          ),
          child: Row(
            mainAxisSize: ajustado ? MainAxisSize.min : MainAxisSize.max,
            children: [
              if (semCaixa)
                SizedBox(width: recuo)
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
              Flexible(
                fit: ajustado ? FlexFit.loose : FlexFit.tight,
                child: _umaLinha(
                  ajustado,
                  valor == null
                      ? Text(
                          texto,
                          // mesmo peso das opções da Seção 2
                          style: _textoGrosso(
                            _corRotulo,
                          ).copyWith(fontSize: 15),
                        )
                      : Text.rich(
                          TextSpan(
                            style: TextStyle(fontSize: 15, color: _corRotulo),
                            children: [
                              TextSpan(text: texto),
                              TextSpan(
                                text: valor,
                                // 14: o negrito (e os números) parecem maiores
                                // que o texto de 15
                                style: _textoGrosso(
                                  _corRotulo,
                                ).copyWith(fontSize: 14),
                              ),
                              TextSpan(text: depois),
                            ],
                          ),
                        ),
                ),
              ),
              // botão no fim da linha (ex.: Registrar da Seção 2)
              if (acao != null) ...[const SizedBox(width: 8), acao],
            ],
          ),
        ),
      ),
    );
  }
}
