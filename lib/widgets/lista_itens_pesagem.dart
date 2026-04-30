import 'package:flutter/material.dart';

class ListaItensPesagem extends StatelessWidget {
  final List<Map<String, dynamic>> itensPesados;
  final int? indexSendoEditado;
  final int? itemExpandidoIndex;
  final void Function(int index) onEditar;
  final void Function(int index, String identificacao) onExcluir;
  final void Function(int? index) onExpansionChanged;

  const ListaItensPesagem({
    super.key,
    required this.itensPesados,
    required this.indexSendoEditado,
    required this.itemExpandidoIndex,
    required this.onEditar,
    required this.onExcluir,
    required this.onExpansionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 6.0),
      itemCount: itensPesados.length,
      itemBuilder: (context, index) {
        final item = itensPesados[index];
        final bool emEdicao = indexSendoEditado == index;
        final bool estaExpandido = itemExpandidoIndex == index;

        return Container(
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            color: emEdicao ? Colors.blue.shade50 : Colors.transparent,
            border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
          ),
          child: ExpansionTile(
            key: GlobalKey(),
            initiallyExpanded: estaExpandido,
            onExpansionChanged: (expanded) {
              onExpansionChanged(expanded ? index : null);
            },
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
                    "${item['peso']}kg | ${item['sexo']} | ${item['raca']}${item['criterio'].toString().isNotEmpty ? ' | Apt: ${item['criterio']}' : ''}",
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
            trailing: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: -5,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                  onPressed: () => onEditar(index),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete, color: Colors.blue, size: 20),
                  onPressed: () =>
                      onExcluir(index, item['alfaNumerico'].toString()),
                ),
                Icon(
                  estaExpandido
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Colors.grey,
                  size: 22,
                ),
              ],
            ),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Pelagem: ${item['pelagem']} | ${item['nascimento']} | Mãe: ${item['maeBrinco']}",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade800,
                      ),
                    ),

                    // OBS NORMAL (digitada pelo usuário)
                    if (item['obs'].toString().trim().isNotEmpty)
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

                    // MENSAGEM DE REPETIDO (separada)
                    if (item['mensRepetido'].toString().trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          "${item['mensRepetido']}",
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
