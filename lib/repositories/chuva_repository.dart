import '../data/daos/chuva_dao.dart';
import '../services/chuva_sync_service.dart';
import '../services/connectivity_service.dart';

/// Camada única de acesso à chuva — offline-first, mesmo padrão do
/// PesagemRepository: toda leitura/gráfico vem do cache local (fonte de
/// verdade do que este aparelho conhece); toda escrita grava local primeiro
/// (nunca espera rede) e tenta subir na hora se houver internet, deixando o
/// ChuvaSyncService reenviar depois em caso de falha.
class ChuvaRepository {
  ChuvaRepository._();
  static final ChuvaRepository instance = ChuvaRepository._();

  bool get _online => ConnectivityService.instance.temInternetReal;

  /// O id de fazenda que vem do login (userFazendas) é o tbl_pessoa_id
  /// formatado com zeros à esquerda (ex: "000000056"), mesmo padrão usado
  /// nos selects do sistema web. Mas o que a exportação do servidor
  /// (list.php) devolve pra cada registro de chuva é o inteiro puro (56),
  /// e é isso que fica salvo em chuva_cache.fazenda_id — normalizar aqui,
  /// no único ponto de entrada do repositório, garante que toda leitura e
  /// escrita usa a mesma chave, não importa de onde o id veio. Sem isso, a
  /// tela buscava por "000000056" e nunca encontrava o que estava salvo
  /// como "56" (bug real: gráfico sempre vazio, mesmo com o cache
  /// populado).
  String _normalizarFazendaId(String fazendaId) {
    final numero = int.tryParse(fazendaId);
    return numero != null ? numero.toString() : fazendaId;
  }

  String formatarData(DateTime data) {
    final ano = data.year.toString().padLeft(4, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final dia = data.day.toString().padLeft(2, '0');
    return '$ano-$mes-$dia';
  }

  /// Volume já lançado nessa data/fazenda, se houver — para avisar antes de
  /// sobrescrever (mesmo aviso do sistema web).
  Future<double?> buscarVolumeExistente({
    required String bd,
    required String fazendaId,
    required DateTime data,
  }) async {
    final linha = await ChuvaDao.instance.buscarPorData(
      bd: bd,
      fazendaId: fazendaId,
      data: formatarData(data),
    );
    if (linha == null) return null;
    return (linha['volume'] as num).toDouble();
  }

  /// Grava o volume do dia. Sempre confirma sucesso pro usuário assim que
  /// termina de salvar localmente — a subida para o servidor (imediata, se
  /// online, ou depois, via ChuvaSyncService) é transparente pra tela.
  Future<void> gravar({
    required String bd,
    required String fazendaId,
    required DateTime data,
    required double volume,
    String? usuario,
  }) async {
    final dataStr = formatarData(data);

    await ChuvaDao.instance.salvarLocal(
      bd: bd,
      fazendaId: fazendaId,
      data: dataStr,
      volume: volume,
      usuario: usuario,
    );

    if (_online) {
      final ok = await ChuvaSyncService.instance.enviarUm(
        bd: bd,
        fazendaId: fazendaId,
        data: dataStr,
        volume: volume,
        usuario: usuario,
      );
      if (ok) {
        await ChuvaDao.instance.marcarSincronizado(
          bd: bd,
          fazendaId: fazendaId,
          data: dataStr,
        );
      }
      // Falhou mesmo online (timeout, erro do servidor): já está salvo
      // localmente com sincronizado = 0 — ChuvaSyncService tenta de novo
      // sozinho (conectividade voltando ou o timer de 30s).
    }
  }

  Future<int> contarPendentes(String bd) =>
      ChuvaDao.instance.contarPendentes(bd);

  /// Gráfico mensal (ano informado) — 12 itens, jan..dez.
  Future<List<Map<String, num>>> graficoMensal({
    required String bd,
    required String fazendaId,
    required int ano,
  }) {
    return ChuvaDao.instance.agregarPorMes(
      bd: bd,
      fazendaId: fazendaId,
      ano: ano,
    );
  }

  /// Gráfico anual — 5 itens, ano-4..ano.
  Future<List<Map<String, num>>> graficoAnual({
    required String bd,
    required String fazendaId,
    required int anoFinal,
  }) {
    return ChuvaDao.instance.agregarPorAno(
      bd: bd,
      fazendaId: fazendaId,
      anoFinal: anoFinal,
    );
  }
}
