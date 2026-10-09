import 'package:flutter/material.dart';

/// Tarja azul clara com o nome da fazenda escolhida (e, opcionalmente, mais
/// informações em [complemento]) e o ícone de edição para trocar de fazenda.
/// Mesmo visual do Mapa de Gado.
class TarjaFazendaWidget extends StatelessWidget {
  final String nomeFazenda;

  /// Só mostra o ícone de edição quando existe outra fazenda para escolher.
  final bool temOutras;
  final VoidCallback onTrocar;
  final List<InlineSpan> complemento;

  /// Opcional: fica dentro da tarja, antes do nome da fazenda (no Mapa de
  /// Gado, o ícone que troca Tabuleiro <-> Satélite).
  final Widget? prefixo;

  const TarjaFazendaWidget({
    super.key,
    required this.nomeFazenda,
    required this.temOutras,
    required this.onTrocar,
    this.complemento = const [],
    this.prefixo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF1F3F6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          prefixo == null ? 10 : 2,
          prefixo == null ? 8 : 2,
          temOutras ? 0 : 10,
          prefixo == null ? 8 : 2,
        ),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            if (prefixo != null) prefixo!,
            Expanded(
              // Sempre em UMA linha: se o texto não couber (nome comprido,
              // total de animais com 4 ou 5 dígitos), a fonte encolhe um
              // pouco em vez de quebrar a linha ou encostar no ícone de
              // trocar de fazenda.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                    children: [
                      TextSpan(text: nomeFazenda),
                      ...complemento,
                    ],
                  ),
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ),
            if (temOutras)
              IconButton(
                onPressed: onTrocar,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_note, color: Colors.blue, size: 22),
                tooltip: 'Trocar de fazenda',
              ),
          ],
        ),
      ),
    );
  }
}

/// Modal "Selecione a Fazenda". Devolve o id escolhido, ou null se cancelou.
Future<String?> escolherFazendaModal(
  BuildContext context, {
  required List<dynamic> fazendas,
  required String? fazendaSelecionada,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showDialog<String>(
    context: context,
    requestFocus: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text(
        'Selecione a Fazenda',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final f in fazendas)
              ListTile(
                dense: true,
                selected: (f as Map)['id'].toString() == fazendaSelecionada,
                selectedTileColor: Colors.grey.shade200,
                title: Text(
                  f['nome'].toString().toUpperCase(),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF455A64),
                  ),
                ),
                onTap: () => Navigator.pop(ctx, f['id'].toString()),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
      ],
    ),
  );
}
