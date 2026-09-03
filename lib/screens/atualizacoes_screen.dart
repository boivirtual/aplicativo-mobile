import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/daos/animal_cache_dao.dart';

/// Tela de conferência do que está gravado neste aparelho — pensada pro
/// TESTADOR conseguir checar sozinho itens do checklist de testes (ex:
/// "cadastro de animais baixado bate com o total esperado", "instalei a
/// build certa?") sem precisar de ferramenta técnica (antes só dava pra
/// ver isso puxando o banco via cabo).
class AtualizacoesScreen extends StatefulWidget {
  final VoidCallback onBack;
  const AtualizacoesScreen({super.key, required this.onBack});

  @override
  State<AtualizacoesScreen> createState() => _AtualizacoesScreenState();
}

class _AtualizacoesScreenState extends State<AtualizacoesScreen> {
  static const _corBarra = Color(0xFF18385F);

  /// Ano de 2 dígitos usado SÓ pra exibição (junto com o build number, que
  /// não pode carregar o ano — ver comentário em [_formatarBuildComoData]).
  /// Atualizar em janeiro de cada ano.
  static const _anoExibicao = '26';
  static const _anoExibicaoCompleto = '2026';

  bool _carregando = true;
  String _versaoNumero = '-';
  String _versaoData = '-';
  String _usuario = '-';
  String _cnpj = '-';
  List<dynamic> _fazendas = [];
  int _totalAnimaisCache = 0;
  String? _ultimaAtualizacaoCache;

  @override
  void initState() {
    super.initState();
    _carregarTudo();
  }

  /// O build number do pubspec.yaml (depois do "+") é MÊS+DIA+HORA+MINUTO
  /// da build, formato MMDDHHmm (ex: "09030926" = 03/09 às 09:26) — sem
  /// ano, porque o Android exige que esse número caiba num inteiro de 32
  /// bits (até ~2,1 bilhões); com ano junto (ex: "2609030926") o número
  /// passa de 2,6 bilhões e o build falha direto no Gradle. O ano exibido
  /// aqui ([_anoExibicao]) é só cosmético, não vem do build number. A hora
  /// importa porque pode sair mais de uma build no mesmo dia.
  ///
  /// O Android guarda o build number como NÚMERO de verdade, não texto —
  /// então o zero à esquerda do mês (janeiro a setembro, "0X") se perde ao
  /// ler de volta: "09030926" volta como "9030926" (só 7 dígitos, bug real
  /// visto ao vivo). Por isso completa com zero à esquerda até 8 dígitos
  /// antes de interpretar. Se algum dia o build number voltar a ser
  /// sequencial (1, 2, 3...) em vez de data, isso aqui não retorna nada e
  /// quem chamou mostra o valor cru.
  ({String mes, String dia, String hora, String minuto, String normalizado})?
  _partesDoBuild(String buildNumber) {
    final normalizado = buildNumber.padLeft(8, '0');
    if (!RegExp(r'^\d{8}$').hasMatch(normalizado)) return null;
    return (
      mes: normalizado.substring(0, 2),
      dia: normalizado.substring(2, 4),
      hora: normalizado.substring(4, 6),
      minuto: normalizado.substring(6, 8),
      normalizado: normalizado,
    );
  }

  Future<void> _carregarTudo() async {
    setState(() => _carregando = true);

    final packageInfo = await PackageInfo.fromPlatform();

    final prefs = await SharedPreferences.getInstance();
    final usuario = prefs.getString('userName') ?? '-';
    final cnpj = prefs.getString('userCNPJ') ?? '-';
    final fazendasJson = prefs.getString('userFazendas');
    final fazendas = fazendasJson != null ? json.decode(fazendasJson) : [];

    final totalAnimais = await AnimalCacheDao.instance.contarTotal();
    final ultimaAtualizacao = await AnimalCacheDao.instance
        .buscarUltimaAtualizacao();

    if (!mounted) return;
    final partes = _partesDoBuild(packageInfo.buildNumber);
    setState(() {
      _versaoNumero = partes == null
          ? '${packageInfo.version}+${packageInfo.buildNumber}'
          : '${packageInfo.version}+$_anoExibicao${partes.normalizado}';
      _versaoData = partes == null
          ? packageInfo.buildNumber
          : '${partes.dia}/${partes.mes}/$_anoExibicaoCompleto '
                '${partes.hora}:${partes.minuto}';
      _usuario = usuario;
      _cnpj = cnpj;
      _fazendas = fazendas;
      _totalAnimaisCache = totalAnimais;
      _ultimaAtualizacaoCache = ultimaAtualizacao;
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
          "Atualizações",
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
                  _secao("Versão do App", [
                    _linha("Número", _versaoNumero, destaque: true),
                    _linha("Data desta versão", _versaoData),
                  ]),
                  _secao("Conta logada", [
                    _linha("Usuário", _usuario),
                    _linha("CNPJ / Banco", _cnpj),
                    _linhaLista(
                      "Fazendas com acesso",
                      _fazendas.isEmpty
                          ? ["Nenhuma"]
                          : _fazendas
                                .map((f) => (f as Map)['nome']?.toString())
                                .whereType<String>()
                                .toList(),
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
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      "Confira se a versão instalada é a combinada, e compare o "
                      "total de animais baixados com o total esperado no "
                      "sistema web.",
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
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              rotulo,
              style: const TextStyle(fontSize: 11, color: Colors.black87),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: destaque ? 15 : 11,
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

  /// Título numa linha, valores um por linha embaixo, alinhados à esquerda
  /// — diferente de [_linha] (rótulo e valor lado a lado): usado quando o
  /// valor é uma lista de nomes que não cabe bem espremida numa coluna
  /// estreita (ex: nomes de fazenda quebrando/enrolando no meio da palavra).
  Widget _linhaLista(String rotulo, List<String> valores) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rotulo,
            style: const TextStyle(fontSize: 11, color: Colors.black87),
          ),
          const SizedBox(height: 4),
          ...valores.map(
            (v) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                v,
                textAlign: TextAlign.left,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
