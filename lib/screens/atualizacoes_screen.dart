import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/daos/animal_cache_dao.dart';
import '../data/daos/pesagem_local_dao.dart';
import '../services/sync_service.dart';

/// Tela de conferência do que está gravado neste aparelho — pensada pro
/// TESTADOR conseguir checar sozinho itens do checklist de testes (ex:
/// "cadastro de animais baixado bate com o total esperado") sem precisar de
/// ferramenta técnica (antes só dava pra ver isso puxando o banco via cabo).
class DiagnosticoScreen extends StatefulWidget {
  final VoidCallback onBack;
  const DiagnosticoScreen({super.key, required this.onBack});

  @override
  State<DiagnosticoScreen> createState() => _DiagnosticoScreenState();
}

class _DiagnosticoScreenState extends State<DiagnosticoScreen> {
  static const _corBarra = Color(0xFF18385F);

  bool _carregando = true;
  String _usuario = '-';
  String _cnpj = '-';
  List<dynamic> _fazendas = [];
  int _totalAnimaisCache = 0;
  String? _ultimaAtualizacaoCache;
  int _totalPesagensLocais = 0;

  StreamSubscription<int>? _subPendentes;
  StreamSubscription<int>? _subConflitos;
  int _pendentesSync = 0;
  int _conflitos = 0;

  @override
  void initState() {
    super.initState();
    _subPendentes = SyncService.instance.pendentes.listen((qtd) {
      if (mounted) setState(() => _pendentesSync = qtd);
    });
    _subConflitos = SyncService.instance.conflitos.listen((qtd) {
      if (mounted) setState(() => _conflitos = qtd);
    });
    SyncService.instance.atualizarContagemPendentes();
    _carregarTudo();
  }

  @override
  void dispose() {
    _subPendentes?.cancel();
    _subConflitos?.cancel();
    super.dispose();
  }

  Future<void> _carregarTudo() async {
    setState(() => _carregando = true);

    final prefs = await SharedPreferences.getInstance();
    final usuario = prefs.getString('userName') ?? '-';
    final cnpj = prefs.getString('userCNPJ') ?? '-';
    final fazendasJson = prefs.getString('userFazendas');
    final fazendas = fazendasJson != null ? json.decode(fazendasJson) : [];

    final totalAnimais = await AnimalCacheDao.instance.contarTotal();
    final ultimaAtualizacao = await AnimalCacheDao.instance
        .buscarUltimaAtualizacao();
    final totalPesagens = await PesagemLocalDao.instance.contarTotalLocal(
      cnpj,
    );

    SyncService.instance.atualizarContagemPendentes();

    if (!mounted) return;
    setState(() {
      _usuario = usuario;
      _cnpj = cnpj;
      _fazendas = fazendas;
      _totalAnimaisCache = totalAnimais;
      _ultimaAtualizacaoCache = ultimaAtualizacao;
      _totalPesagensLocais = totalPesagens;
      _carregando = false;
    });
  }

  String _formatarData(String? iso) {
    if (iso == null) return 'Nunca';
    try {
      final d = DateTime.parse(iso);
      String dois(int n) => n.toString().padLeft(2, '0');
      return '${dois(d.day)}/${dois(d.month)}/${d.year} às ${dois(d.hour)}:${dois(d.minute)}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _corBarra,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: widget.onBack,
        ),
        title: const Text(
          "Conferir Dados do Aparelho",
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _carregando ? null : _carregarTudo,
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregarTudo,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _secao("Conta logada", [
                    _linha("Usuário", _usuario),
                    _linha("CNPJ / Banco", _cnpj),
                    _linha(
                      "Fazendas com acesso",
                      _fazendas.isEmpty
                          ? "Nenhuma"
                          : _fazendas
                                .map((f) => (f as Map)['nome']?.toString())
                                .whereType<String>()
                                .join(', '),
                    ),
                  ]),
                  _secao("Cadastro de animais (cache local)", [
                    _linha(
                      "Total de animais baixados",
                      "$_totalAnimaisCache",
                      destaque: true,
                    ),
                    _linha(
                      "Última atualização",
                      _formatarData(_ultimaAtualizacaoCache),
                    ),
                  ]),
                  _secao("Pesagens neste aparelho", [
                    _linha("Total salvas localmente", "$_totalPesagensLocais"),
                    _linha(
                      "Pendentes de sincronização",
                      "$_pendentesSync",
                      alerta: _pendentesSync > 0,
                    ),
                    _linha(
                      "Recusadas pelo servidor (revisão)",
                      "$_conflitos",
                      alerta: _conflitos > 0,
                    ),
                  ]),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      "Use esses números para conferir o checklist de testes — "
                      "por exemplo, comparando o total de animais baixados com "
                      "o total esperado no sistema web.",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _secao(String titulo, List<Widget> linhas) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: _corBarra,
            ),
          ),
          const Divider(height: 16),
          ...linhas,
        ],
      ),
    );
  }

  Widget _linha(
    String rotulo,
    String valor, {
    bool destaque = false,
    bool alerta = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              rotulo,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: destaque ? 18 : 13,
                fontWeight: destaque ? FontWeight.bold : FontWeight.w600,
                color: alerta
                    ? Colors.red[700]
                    : (destaque ? _corBarra : Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
