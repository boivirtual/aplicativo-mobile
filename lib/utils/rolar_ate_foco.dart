import 'package:flutter/widgets.dart';

/// Rola até o campo em edição depois que o teclado termina de abrir.
///
/// Nos modais (Dialog) o espaço só encolhe ao fim da animação do teclado,
/// e a rolagem automática do Flutter acontece antes disso — o campo (ex.: o
/// Volume da Aplicação) ficava escondido atrás do teclado.
void rolarAteCampoEmFoco() {
  Future.delayed(const Duration(milliseconds: 350), () {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null || !ctx.mounted) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  });
}
