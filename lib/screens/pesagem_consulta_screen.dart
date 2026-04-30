import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class PesagemConsultaScreen extends StatefulWidget {
  final String fazendaSelecionada;
  final String motivoSelecionado;
  final String descricaoLote;
  final String qtdAPesar;
  final int idPesagemExistente;
  final VoidCallback onBack;

  const PesagemConsultaScreen({
    super.key,
    required this.fazendaSelecionada,
    required this.motivoSelecionado,
    required this.descricaoLote,
    required this.qtdAPesar,
    required this.idPesagemExistente,
    required this.onBack,
  });

  @override
  State<PesagemConsultaScreen> createState() => _PesagemConsultaScreenState();
}

class _PesagemConsultaScreenState extends State<PesagemConsultaScreen> {
  String? cnpjParaBanco;
  bool carregandoItens = false;
  final List<Map<String, dynamic>> _itensPesados = [];
  int? _itemExpandidoIndex;

  final Map<String, String> motivos = {
    '001': 'Nascimento',
    '002': 'Desmama',
    '003': 'Venda',
    '004': 'Compra',
    '005': 'Tranferência',
    '011': 'Controle Ganho de Peso',
    '012': 'Machos acima 8 meses',
    '013': 'Femeas 08 a 24 meses',
    '016': 'MÃE de desmama',
  };

  @override
  void initState() {
    super.initState();
    _carregarDadosBase();
  }

  Future<void> _carregarDadosBase() async {
    final prefs = await SharedPreferences.getInstance();
    cnpjParaBanco = prefs.getString('userCNPJ');
    _carregarItensDoServidor();
  }

  Future<void> _carregarItensDoServidor() async {
    setState(() => carregandoItens = true);
    try {
      final url = Uri.parse(
        "https://agrolandes.com.br/teste_boivirtual/sistema/api/rest/pesagem/get_pesagem_completa.php",
      );
      final response = await http.post(
        url,
        body: json.encode({
          "bd": cnpjParaBanco,
          "id_pesagem": widget.idPesagemExistente,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          final List itensBanco = data['itens'];
          setState(() {
            _itensPesados.clear();
            for (var item in itensBanco) {
              _itensPesados.add({
                'alfaNumerico': item['tbl_ite_pesagem_codigo_animal'],
                'peso': item['tbl_ite_pesagem_peso'],
                'sexo': item['tbl_ite_pesagem_sexo'] == 'Macho' ? 'M' : 'F',
                'nascimento': item['tbl_ite_pesagem_nascimento'],
                'raca': item['tbl_ite_pesagem_raca'],
                'pelagem': item['tbl_ite_pesagem_pelagem'],
                'maeBrinco': item['tbl_ite_pesagem_mae'],
                'obs': item['tbl_ite_pesagem_observacao'],
              });
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Erro ao carregar consulta: $e");
    } finally {
      setState(() => carregandoItens = false);
    }
  }

  int _calcularPesoTotal() {
    return _itensPesados.fold(
      0,
      (sum, item) =>
          sum + (double.tryParse(item['peso'].toString())?.toInt() ?? 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(45.0),
        child: AppBar(
          backgroundColor: const Color(0xFF18385F),
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, size: 24),
            onPressed: widget.onBack,
          ),
          title: const Text(
            'Consulta de Pesagem',
            style: TextStyle(fontSize: 18),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getNomeFazenda(), // AJUSTE: Removida a interpolação desnecessária
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Lote: ${widget.descricaoLote}  |  Qtde a Pesar: ${widget.qtdAPesar}",
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Animais Pesados: ${_itensPesados.length}",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[300],
                  ),
                ),
                Text(
                  "Peso Total: ${_calcularPesoTotal()} Kg",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[300],
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: carregandoItens
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    itemCount: _itensPesados.length,
                    itemBuilder: (context, index) =>
                        _buildListItem(_itensPesados[index], index),
                  ),
          ),
        ],
      ),
    );
  }

  String _getNomeFazenda() {
    return "${widget.fazendaSelecionada} ➔ ${motivos[widget.motivoSelecionado]}";
  }

  Widget _buildListItem(Map<String, dynamic> item, int index) {
    bool estaExpandido = _itemExpandidoIndex == index;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: ExpansionTile(
        key: GlobalKey(),
        initiallyExpanded: estaExpandido,
        onExpansionChanged: (expanded) =>
            setState(() => _itemExpandidoIndex = expanded ? index : null),
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        visualDensity: VisualDensity.compact,
        title: Row(
          children: [
            Text(
              item['alfaNumerico'],
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFF263238),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "${item['peso']}kg | ${item['sexo']} | ${item['nascimento']} | ${item['raca']}",
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF455A64),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        trailing: Icon(
          estaExpandido ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          color: Colors.grey,
          size: 22,
        ),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Pelagem: ${item['pelagem']}  |  Mãe: ${item['maeBrinco']}",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                ),
                if (item['obs'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      "OBS: ${item['obs']}",
                      style: const TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Colors.blueGrey,
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
}
