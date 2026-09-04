import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/chuva_repository.dart';
import '../utils/app_alert.dart';
import '../widgets/cabecalho_fazenda_widget.dart';
import '../widgets/grafico_chuva_widget.dart';

const _mesesAbrev = [
  'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
  'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez',
];
const _mesesCompletos = [
  'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
  'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
];

/// Tela de Chuva — cadastro de precipitação diária e os mesmos dois
/// gráficos da home do sistema web (mensal e histórico de 5 anos), dentro
/// dos padrões visuais do aplicativo.
///
/// Offline-first: o lançamento grava no cache local na hora (nunca espera
/// rede) e sincroniza sozinho — na abertura do app (ver
/// AtualizandoDadosScreen/ChuvaSyncService.sincronizarInicial, mesmo ponto
/// onde o cadastro de animais é atualizado) e, se ficou pendente, assim que
/// a internet voltar. Os gráficos sempre leem do cache local, então
/// funcionam sem internet depois da primeira sincronização.
class ChuvaScreen extends StatefulWidget {
  final VoidCallback onBack;
  const ChuvaScreen({super.key, required this.onBack});

  @override
  State<ChuvaScreen> createState() => _ChuvaScreenState();
}

class _ChuvaScreenState extends State<ChuvaScreen> {
  String? fazendaSelecionada;
  List<dynamic> fazendasCarregadas = [];
  bool carregando = true;

  String? _bd;
  String? _usuario;

  DateTime _dataSelecionada = DateTime.now();
  final _volumeController = TextEditingController();
  bool _salvando = false;

  int _anoGrafico = DateTime.now().year;
  List<Map<String, num>>? _mensal;
  List<Map<String, num>>? _anual;
  bool _carregandoGrafico = false;

  @override
  void initState() {
    super.initState();
    _carregarContexto();
  }

  @override
  void dispose() {
    _volumeController.dispose();
    super.dispose();
  }

  Future<void> _carregarContexto() async {
    final prefs = await SharedPreferences.getInstance();
    final fazendasJson = prefs.getString('userFazendas');
    setState(() {
      _bd = prefs.getString('userCNPJ');
      _usuario = prefs.getString('userName');
      if (fazendasJson != null) {
        fazendasCarregadas = json.decode(fazendasJson);
        if (fazendasCarregadas.length == 1) {
          fazendaSelecionada = fazendasCarregadas[0]['id'].toString();
        }
      }
      carregando = false;
    });
    if (fazendaSelecionada != null) {
      await _recarregarGraficos();
    }
  }

  void _selecionarFazenda(String? id) {
    setState(() => fazendaSelecionada = id);
    _recarregarGraficos();
  }

  Future<void> _recarregarGraficos() async {
    if (fazendaSelecionada == null || _bd == null) return;
    setState(() => _carregandoGrafico = true);
    final mensal = await ChuvaRepository.instance.graficoMensal(
      bd: _bd!,
      fazendaId: fazendaSelecionada!,
      ano: _anoGrafico,
    );
    final anual = await ChuvaRepository.instance.graficoAnual(
      bd: _bd!,
      fazendaId: fazendaSelecionada!,
      anoFinal: _anoGrafico,
    );
    if (!mounted) return;
    setState(() {
      _mensal = mensal;
      _anual = anual;
      _carregandoGrafico = false;
    });
  }

  void _trocarAno(int delta) {
    setState(() => _anoGrafico += delta);
    _recarregarGraficos();
  }

  Future<void> _escolherData() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _dataSelecionada,
      firstDate: DateTime(DateTime.now().year - 10),
      lastDate: DateTime.now(),
      helpText: 'Data da chuva',
      cancelText: 'Cancelar',
      confirmText: 'OK',
    );
    if (escolhida != null) {
      setState(() => _dataSelecionada = escolhida);
    }
  }

  String _formatarDataExibicao(DateTime d) {
    final dia = d.day.toString().padLeft(2, '0');
    final mes = d.month.toString().padLeft(2, '0');
    return '$dia/$mes/${d.year}';
  }

  double? _lerVolumeDigitado() {
    final texto = _volumeController.text.trim().replaceAll(',', '.');
    if (texto.isEmpty) return null;
    return double.tryParse(texto);
  }

  Future<void> _gravar() async {
    if (fazendaSelecionada == null) {
      AppAlert.erro(context, 'Selecione uma fazenda.');
      return;
    }
    final volume = _lerVolumeDigitado();
    if (volume == null || volume < 0) {
      AppAlert.erro(context, 'Informe um volume válido (mm).');
      return;
    }

    final existente = await ChuvaRepository.instance.buscarVolumeExistente(
      bd: _bd ?? '',
      fazendaId: fazendaSelecionada!,
      data: _dataSelecionada,
    );

    if (existente != null) {
      if (!mounted) return;
      AppAlert.confirmacao(
        context,
        mensagem:
            'Já existe volume cadastrado para essa data (${existente.toStringAsFixed(0)} mm). '
            'Deseja sobrescrever para ${volume.toStringAsFixed(0)} mm?',
        onConfirmar: () => _confirmarGravacao(volume),
      );
      return;
    }

    await _confirmarGravacao(volume);
  }

  Future<void> _confirmarGravacao(double volume) async {
    setState(() => _salvando = true);
    try {
      await ChuvaRepository.instance.gravar(
        bd: _bd ?? '',
        fazendaId: fazendaSelecionada!,
        data: _dataSelecionada,
        volume: volume,
        usuario: _usuario,
      );
      if (!mounted) return;
      _volumeController.clear();
      await _recarregarGraficos();
      if (!mounted) return;
      await AppAlert.sucesso(context, 'Volume registrado com sucesso.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  String _getNomeFazenda(String id) {
    final fazenda = fazendasCarregadas.firstWhere(
      (f) => f['id'].toString() == id,
      orElse: () => {'nome': 'Não encontrada'},
    );
    return fazenda['nome'].toString().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Chuva', style: TextStyle(fontSize: 18, color: Colors.white)),
        backgroundColor: const Color(0xFF18385F),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: widget.onBack,
        ),
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: Colors.white,
                  child: CabecalhoFazendaWidget(
                    fazendaSelecionada: fazendaSelecionada,
                    fazendasCarregadas: fazendasCarregadas,
                    onChanged: _selecionarFazenda,
                  ),
                ),
                Expanded(
                  child: fazendaSelecionada == null
                      ? Center(
                          child: Text(
                            'Selecione uma fazenda.',
                            style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _recarregarGraficos,
                          child: ListView(
                            padding: const EdgeInsets.all(14),
                            children: [
                              _buildCardRegistro(),
                              const SizedBox(height: 14),
                              _buildResumoMesAtual(),
                              const SizedBox(height: 14),
                              if (_carregandoGrafico && _mensal == null)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 30),
                                  child: Center(child: CircularProgressIndicator()),
                                )
                              else ...[
                                _buildSeletorAno(),
                                const SizedBox(height: 8),
                                if (_mensal != null)
                                  GraficoChuvaWidget(
                                    titulo: 'Precipitação x Dias Chuvosos ($_anoGrafico)',
                                    rotulos: _mesesAbrev,
                                    mm: _mensal!.map((e) => e['mm']!.toDouble()).toList(),
                                    dias: _mensal!.map((e) => e['dias']!.toDouble()).toList(),
                                  ),
                                const SizedBox(height: 14),
                                if (_anual != null)
                                  GraficoChuvaWidget(
                                    titulo: 'Histórico últimos 5 anos',
                                    rotulos: _anual!.map((e) => e['ano'].toString()).toList(),
                                    mm: _anual!.map((e) => e['mm']!.toDouble()).toList(),
                                    dias: _anual!.map((e) => e['dias']!.toDouble()).toList(),
                                  ),
                              ],
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildSeletorAno() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: Color(0xFF18385F)),
          onPressed: () => _trocarAno(-1),
        ),
        Text(
          '$_anoGrafico',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF18385F)),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, color: Color(0xFF18385F)),
          onPressed: _anoGrafico >= DateTime.now().year ? null : () => _trocarAno(1),
        ),
      ],
    );
  }

  Widget _buildCardRegistro() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Registrar Precipitação',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF18385F)),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: GestureDetector(
                  onTap: _escolherData,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Data',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatarDataExibicao(_dataSelecionada)),
                        const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _volumeController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  decoration: const InputDecoration(
                    labelText: 'Volume (mm)',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                disabledBackgroundColor: const Color(0xFF4CAF50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _salvando ? null : _gravar,
              child: _salvando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text(
                      'Gravar',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumoMesAtual() {
    final agora = DateTime.now();
    final mesAtual = agora.month;
    final dadosMes = _mensal?.firstWhere(
      (e) => e['mes'] == mesAtual,
      orElse: () => const {'mes': 0, 'mm': 0, 'dias': 0},
    );
    final mmMes = dadosMes?['mm'] ?? 0;
    final diasMes = dadosMes?['dias'] ?? 0;
    final mmAno = _mensal?.fold<num>(0, (soma, e) => soma + (e['mm'] ?? 0)) ?? 0;

    Widget item(String rotulo, String valor) {
      return Expanded(
        child: Column(
          children: [
            Text(valor, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF18385F))),
            const SizedBox(height: 2),
            Text(rotulo, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          item(_mesesCompletos[mesAtual - 1], ''),
          item('Dias Chuva', diasMes.toString()),
          item('mm Mês', mmMes.toStringAsFixed(0)),
          item('mm Ano', mmAno.toStringAsFixed(0)),
        ],
      ),
    );
  }
}
