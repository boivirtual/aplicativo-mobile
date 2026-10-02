import 'package:flutter/material.dart';

/// Select no padrão dos campos da Pesagem (fundo branco, sem borda, cantos
/// 8): rótulo pequeno em cima e o valor escolhido embaixo, sem cortar. A
/// lista abre logo abaixo do campo (mesmo jeito do select de Fazenda) SEM
/// nenhuma opção pré-marcada — só a já escolhida aparece destacada. O
/// DropdownButton padrão abria com a primeira opção realçada e escondia o
/// valor escolhido atrás do rótulo flutuante.
class SeletorCampoWidget<T> extends StatelessWidget {
  final String rotulo;
  final Color corRotulo;
  final T? valor;
  final List<MapEntry<T, String>> opcoes;
  final ValueChanged<T> onChanged;

  const SeletorCampoWidget({
    required this.rotulo,
    required this.corRotulo,
    required this.valor,
    required this.opcoes,
    required this.onChanged,
  });

  Future<void> _abrir(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (opcoes.isEmpty) return;
    final caixa = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (caixa == null || overlay == null) return;
    final pos = caixa.localToGlobal(Offset.zero, ancestor: overlay);

    final escolhido = await showMenu<T>(
      context: context,
      color: Colors.white,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      constraints: BoxConstraints(
        minWidth: caixa.size.width,
        maxWidth: caixa.size.width < 220 ? 220 : caixa.size.width,
      ),
      position: RelativeRect.fromLTRB(
        pos.dx,
        pos.dy + caixa.size.height + 4,
        overlay.size.width - (pos.dx + caixa.size.width),
        overlay.size.height - pos.dy,
      ),
      items: [
        for (final o in opcoes)
          PopupMenuItem<T>(
            value: o.key,
            height: 42,
            child: Container(
              width: double.infinity,
              alignment: Alignment.centerLeft,
              color: o.key == valor ? Colors.grey.shade200 : null,
              child: Text(
                o.value,
                style: const TextStyle(fontSize: 14, color: Color(0xFF455A64)),
              ),
            ),
          ),
      ],
    );
    if (escolhido != null) onChanged(escolhido);
  }

  @override
  Widget build(BuildContext context) {
    final texto = opcoes
        .where((o) => o.key == valor)
        .map((o) => o.value)
        .firstOrNull;

    return GestureDetector(
      onTap: () => _abrir(context),
      child: Container(
        height: 56,
        padding: const EdgeInsets.only(left: 12, right: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: texto == null
                  ? Text(
                      rotulo,
                      style: TextStyle(fontSize: 14, color: corRotulo),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rotulo,
                          style: TextStyle(fontSize: 11, color: corRotulo),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          texto,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
            ),
            Icon(Icons.arrow_drop_down, color: corRotulo),
          ],
        ),
      ),
    );
  }
}
