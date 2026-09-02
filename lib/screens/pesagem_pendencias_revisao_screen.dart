import 'package:flutter/material.dart';
import '../repositories/pesagem_repository.dart';
import '../services/sync_service.dart';

/// "Pendências de revisão": operações que o servidor recusou explicitamente
/// (não é falta de internet, o servidor respondeu "não pode") e por isso não
/// tentam sincronizar de novo sozinhas. Sem essa tela, esses dados ficavam
/// presos silenciosamente no banco do celular, sem o usuário saber.
class PesagemPendenciasRevisaoScreen extends StatefulWidget {
  final VoidCallback onBack;

  const PesagemPendenciasRevisaoScreen({super.key, required this.onBack});

  @override
  State<PesagemPendenciasRevisaoScreen> createState() =>
      _PesagemPendenciasRevisaoScreenState();
}

class _PesagemPendenciasRevisaoScreenState
    extends State<PesagemPendenciasRevisaoScreen> {
  bool _carregando = true;
  List<Map<String, dynamic>> _pendencias = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final lista = await PesagemRepository.instance.listarPendenciasRevisao();
    if (!mounted) return;
    setState(() {
      _pendencias = lista;
      _carregando = false;
    });
  }

  String _formatarData(dynamic isoTexto) {
    final data = DateTime.tryParse(isoTexto?.toString() ?? '');
    if (data == null) return '';
    final dd = data.day.toString().padLeft(2, '0');
    final mm = data.month.toString().padLeft(2, '0');
    final hh = data.hour.toString().padLeft(2, '0');
    final min = data.minute.toString().padLeft(2, '0');
    return '$dd/$mm ${hh}h$min';
  }

  IconData _iconePorTipo(String tipo) {
    switch (tipo) {
      case 'CRIAR_PESAGEM':
      case 'EDITAR_PESAGEM':
        return Icons.assignment_outlined;
      case 'EXCLUIR_ITEM':
        return Icons.delete_outline;
      default:
        return Icons.scale_outlined;
    }
  }

  Future<void> _tentarDeNovo(Map<String, dynamic> pendencia) async {
    await PesagemRepository.instance.reenviarPendencia(
      pendencia['id'] as int,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Colocado na fila — sincronizando...")),
    );
    await SyncService.instance.sincronizarAgora(ignorarRecuo: true);
    await _carregar();
  }

  Future<void> _confirmarDescarte(Map<String, dynamic> pendencia) async {
    final ehItem =
        pendencia['tipo'] == 'SALVAR_ITEM' ||
        pendencia['tipo'] == 'EDITAR_ITEM';
    final descricaoAlvo = pendencia['animalCodigo'] != null
        ? "o peso do animal ${pendencia['animalCodigo']}"
        : "esta operação (${pendencia['rotuloTipo']})";

    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text(
          "Descartar pendência",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          ehItem
              ? "$descricaoAlvo continua salvo neste aparelho, mas nunca será enviado ao servidor. "
                  "Use isso só se tiver certeza — não dá pra desfazer depois."
              : "$descricaoAlvo nunca será enviada ao servidor. Não dá pra desfazer depois.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              "CANCELAR",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              "DESCARTAR",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    await PesagemRepository.instance.descartarPendencia(
      pendencia['id'] as int,
    );
    await _carregar();
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
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: widget.onBack,
          ),
          title: const Text(
            'O que o servidor recusou',
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
      body: Column(
        children: [
          if (!_carregando && _pendencias.isNotEmpty)
            Container(
              width: double.infinity,
              color: Colors.blue[50],
              padding: const EdgeInsets.all(12),
              child: const Text(
                "Isto é diferente de \"pendente de sincronização\": aqui o "
                "aparelho já conseguiu falar com o servidor, e o servidor "
                "respondeu recusando — por isso o app parou de tentar "
                "sozinho e está esperando você decidir.",
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ),
          Expanded(child: _buildCorpo()),
        ],
      ),
    );
  }

  Widget _buildCorpo() {
    return _carregando
          ? const Center(child: CircularProgressIndicator())
          : _pendencias.isEmpty
          ? Center(
              child: Text(
                "Nenhuma pendência — tudo sincronizado.",
                style: TextStyle(color: Colors.grey[500]),
              ),
            )
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _pendencias.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final p = _pendencias[index];
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _iconePorTipo(p['tipo'] as String),
                              size: 18,
                              color: const Color(0xFF18385F),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                [
                                  p['rotuloTipo'],
                                  if (p['animalCodigo'] != null)
                                    'animal ${p['animalCodigo']}',
                                  if (p['lote'] != null) 'lote ${p['lote']}',
                                ].join(' — '),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Text(
                              _formatarData(p['criadoEm']),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          p['mensagemErro'] as String,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => _confirmarDescarte(p),
                              child: const Text(
                                "Descartar",
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                            const SizedBox(width: 4),
                            ElevatedButton(
                              onPressed: () => _tentarDeNovo(p),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF18385F),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                              ),
                              child: const Text(
                                "Tentar de novo",
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
  }
}
