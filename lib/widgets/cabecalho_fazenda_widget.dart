import 'package:flutter/material.dart';

class CabecalhoFazendaWidget extends StatelessWidget {
  final String? fazendaSelecionada;
  final List<dynamic> fazendasCarregadas;
  final ValueChanged<String?> onChanged;
  final String labelSelect;

  const CabecalhoFazendaWidget({
    super.key,
    required this.fazendaSelecionada,
    required this.fazendasCarregadas,
    required this.onChanged,
    this.labelSelect = 'Fazenda',
  });

  String _getNomeFazenda(String id) {
    final fazenda = fazendasCarregadas.firstWhere(
      (f) => f['id'].toString() == id,
      orElse: () => {'nome': 'Não encontrada'},
    );
    return fazenda['nome'].toString().toUpperCase();
  }

  Future<void> _abrirMenu(BuildContext context, GlobalKey campoKey) async {
    if (fazendasCarregadas.isEmpty || fazendasCarregadas.length <= 1) return;

    final renderBox = campoKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
    final size = renderBox.size;

    final escolhido = await showMenu<String>(
      context: context,
      color: Colors.white,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + size.height + 4,
        overlay.size.width - (position.dx + size.width),
        overlay.size.height - position.dy,
      ),
      items: fazendasCarregadas.map((f) {
        final id = f['id'].toString();
        final nome = f['nome'].toString().toUpperCase();
        final selecionada = id == fazendaSelecionada;

        return PopupMenuItem<String>(
          value: id,
          height: 42,
          child: Container(
            alignment: Alignment.centerLeft,
            color: selecionada ? Colors.grey.shade200 : Colors.transparent,
            child: Text(
              nome,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: Color(0xFF455A64)),
            ),
          ),
        );
      }).toList(),
    );

    if (escolhido != null) {
      onChanged(escolhido);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (fazendasCarregadas.isEmpty) {
      return const SizedBox.shrink();
    }

    final bool temMaisDeUma = fazendasCarregadas.length > 1;
    final GlobalKey campoKey = GlobalKey();

    final String textoExibido = fazendaSelecionada != null
        ? _getNomeFazenda(fazendaSelecionada!)
        : 'Selecione';

    final Color textoCor = fazendaSelecionada != null
        ? const Color(0xFF455A64)
        : const Color(0xFF607D8B);

    return Container(
      width: double.infinity,
      color: const Color(0xFFF1F3F6),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: GestureDetector(
        onTap: temMaisDeUma ? () => _abrirMenu(context, campoKey) : null,
        child: Container(
          key: campoKey,
          height: 55,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.location_on, color: Color(0xFF18385F), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      labelSelect,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF607D8B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      textoExibido,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: textoCor,
                        fontWeight: fazendaSelecionada != null
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              if (temMaisDeUma)
                const Icon(Icons.arrow_drop_down, color: Color(0xFF18385F)),
            ],
          ),
        ),
      ),
    );
  }
}
