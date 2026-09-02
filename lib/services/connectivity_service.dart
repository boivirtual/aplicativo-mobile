import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Nível de conectividade real, não só "tem uma interface de rede ativa".
enum NivelConexao {
  semInternet,
  internetRuim,
  internetOk,
}

/// Serviço único de conectividade, compartilhado pelo app inteiro.
///
/// Substitui os 3 blocos idênticos que existiam em main_container.dart,
/// pesagem_screen.dart e pesagem_itens_screen.dart. Mantém exatamente a mesma
/// heurística que já existia: "tem barra de sinal" (connectivity_plus) não é
/// suficiente — só considera internet de verdade depois de um lookup DNS bem
/// sucedido em agrolandes.com.br.
///
/// As telas continuam responsáveis por assinar/cancelar sua própria
/// StreamSubscription (mesmo padrão de antes), só que ouvindo este serviço em
/// vez de instanciar Connectivity() e repetir a lógica de DNS.
class ConnectivityService {
  ConnectivityService._() {
    _iniciar();
  }

  static final ConnectivityService instance = ConnectivityService._();

  /// Host usado no lookup DNS que confirma internet de verdade. Não é
  /// `const` de propósito: os testes de rede ruim
  /// (test/sync_rede_ruim_test.dart) apontam isso pra "localhost" antes de
  /// rodar, pra não depender de internet real (nem de conseguir resolver o
  /// domínio de produção) dentro do ambiente de teste. Em produção nunca
  /// muda do valor abaixo.
  static String hostParaChecagem = 'agrolandes.com.br';

  final StreamController<NivelConexao> _controller =
      StreamController<NivelConexao>.broadcast();

  NivelConexao _ultimoNivel = NivelConexao.internetOk;
  NivelConexao get nivelAtual => _ultimoNivel;

  /// Stream de mudanças de nível de conexão. Emite o nível assim que alguém
  /// assina (replay do último valor conhecido), e depois a cada mudança real.
  Stream<NivelConexao> get status async* {
    yield _ultimoNivel;
    yield* _controller.stream;
  }

  bool get temInternetReal => _ultimoNivel == NivelConexao.internetOk;

  void _iniciar() {
    _verificarConexaoAtual();
    Connectivity().onConnectivityChanged.listen(_processarStatusInternet);

    // onConnectivityChanged só dispara quando o TIPO de rede muda (ex: wifi
    // -> dados -> nenhuma). No campo é comum a internet cair e voltar sem
    // trocar de tipo (ex: continua "conectado" no wifi/dados, só sem sinal
    // de verdade um tempo) — sem essa reverificação periódica, o app ficava
    // preso pra sempre no último nível medido (geralmente "ruim"), mesmo
    // depois da internet voltar de verdade.
    Timer.periodic(
      const Duration(seconds: 15),
      (_) => _verificarConexaoAtual(),
    );
  }

  Future<void> _verificarConexaoAtual() async {
    final result = await Connectivity().checkConnectivity();
    await _processarStatusInternet(result);
  }

  /// Força uma nova verificação agora (usado pelo botão manual "Sincronizar
  /// agora" antes de tentar a fila, para não depender só do último evento).
  Future<NivelConexao> verificarAgora() async {
    final result = await Connectivity().checkConnectivity();
    await _processarStatusInternet(result);
    return _ultimoNivel;
  }

  Future<void> _processarStatusInternet(List<ConnectivityResult> results) async {
    if (results.contains(ConnectivityResult.none)) {
      _emitir(NivelConexao.semInternet);
      return;
    }

    try {
      final res = await InternetAddress.lookup(
        hostParaChecagem,
      ).timeout(const Duration(seconds: 3));

      if (res.isNotEmpty && res[0].rawAddress.isNotEmpty) {
        _emitir(NivelConexao.internetOk);
      } else {
        _emitir(NivelConexao.internetRuim);
      }
    } catch (_) {
      _emitir(NivelConexao.internetRuim);
    }
  }

  void _emitir(NivelConexao nivel) {
    final mudou = nivel != _ultimoNivel;
    _ultimoNivel = nivel;
    if (mudou) {
      _controller.add(nivel);
    }
  }

  /// Usado apenas em testes automatizados, para simular offline/online sem
  /// depender do plugin de conectividade real. Nunca chamado em código de
  /// produção.
  void forcarNivelParaTeste(NivelConexao nivel) => _emitir(nivel);
}
