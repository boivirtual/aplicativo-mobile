import 'package:flutter/material.dart';

/// Modal "Tratamento N" do Resumo Diário (Seção 3 — Sanidade Animal).
/// Fundo cinza no padrão dos outros modais, (x) no canto para fechar sem
/// criar nada, conteúdo com rolagem e o botão "Confirmar Tratamento".
///
/// Os campos do tratamento vêm nas próximas etapas. Devolve os dados do
/// tratamento ao confirmar; null ao fechar pelo (x).
class TratamentoModal extends StatefulWidget {
  /// Número do tratamento (1, 2, 3...).
  final int numero;

  /// Dados de um tratamento já incluído (editar); null = novo.
  final Map<String, dynamic>? dados;

  const TratamentoModal({super.key, required this.numero, this.dados});

  @override
  State<TratamentoModal> createState() => _TratamentoModalState();
}

class _TratamentoModalState extends State<TratamentoModal> {
  static const _azulTitulo = Color(0xFF18385F);
  static const _verde = Color(0xFF4CAF50);
  static final _corRotulo = Colors.blueGrey[800]!;

  void _confirmar() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context, <String, dynamic>{...?widget.dados});
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 44, 6),
                  child: Text(
                    'Tratamento ${widget.numero}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, color: _azulTitulo),
                  ),
                ),
                // conteúdo com rolagem (os campos vêm nas próximas etapas)
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Os campos do tratamento vêm nas próximas etapas.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: _corRotulo,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _verde,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _confirmar,
                      child: const Text(
                        'Confirmar Tratamento',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // (x) no canto: fecha sem criar nada
          Positioned(
            top: -10,
            right: -10,
            child: Material(
              color: _azulTitulo,
              shape: const CircleBorder(
                side: BorderSide(color: Colors.white, width: 2),
              ),
              elevation: 3,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.close, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
