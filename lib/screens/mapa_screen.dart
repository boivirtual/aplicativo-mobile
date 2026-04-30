import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/cabecalho_fazenda_widget.dart';

class MapaScreen extends StatefulWidget {
  final VoidCallback onBack; // Recebe a função para voltar à Home
  const MapaScreen({super.key, required this.onBack});

  @override
  State<MapaScreen> createState() => _MapaScreenState();
}

class _MapaScreenState extends State<MapaScreen> {
  String? fazendaSelecionada;
  List<dynamic> fazendasCarregadas = [];
  bool carregando = true;

  @override
  void initState() {
    super.initState();
    _carregarFazendas();
  }

  Future<void> _carregarFazendas() async {
    final prefs = await SharedPreferences.getInstance();
    final String? fazendasJson = prefs.getString('userFazendas');
    if (fazendasJson != null) {
      setState(() {
        fazendasCarregadas = json.decode(fazendasJson);
        if (fazendasCarregadas.length == 1) {
          fazendaSelecionada = fazendasCarregadas[0]['id'].toString();
        }
        carregando = false;
      });
    } else {
      setState(() => carregando = false);
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Mapa de Gado',
          style: TextStyle(fontSize: 18, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF18385F),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: widget.onBack, // Volta para a Home
        ),
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                CabecalhoFazendaWidget(
                  fazendaSelecionada: fazendaSelecionada,
                  fazendasCarregadas: fazendasCarregadas,
                  onChanged: (val) => setState(() => fazendaSelecionada = val),
                ),
                Expanded(
                  child: Center(
                    child: fazendaSelecionada == null
                        ? Text(
                            "Selecione uma fazenda para visualizar o mapa.",
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        : Text(
                            "Aqui aparecerão os dados da fazenda:\n${_getNomeFazenda(fazendaSelecionada!)}",
                            textAlign: TextAlign.center,
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}
