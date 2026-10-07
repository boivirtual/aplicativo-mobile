import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Banco de dados local (SQLite) usado para trabalhar offline na Pesagem.
///
/// Guarda pesagens/itens ainda não confirmados pelo servidor, a fila de
/// sincronização (outbox) e o cache do cadastro de animais das fazendas do
/// usuário. Nenhuma tela acessa este arquivo diretamente — sempre através dos
/// DAOs locais (lib/data/daos/) e dos repositórios (lib/repositories/).
class LocalDatabase {
  LocalDatabase._();
  static final LocalDatabase instance = LocalDatabase._();

  static const int _versaoSchema = 11;

  /// Nome do arquivo do banco — não é `const` de propósito: os testes
  /// automatizados rodam vários arquivos em paralelo (isolates diferentes),
  /// e todos abrindo o MESMO arquivo físico no disco causava
  /// "database is locked" de vez em quando quando o `flutter test` (sem
  /// apontar um arquivo específico) rodava tudo de uma vez. Cada arquivo de
  /// teste seta um nome próprio no início do `main()`. Em produção nunca
  /// muda do valor abaixo.
  static String nomeArquivo = 'boivirtual_offline.db';

  Database? _db;

  Future<Database> get database async {
    _db ??= await _abrir();
    return _db!;
  }

  Future<Database> _abrir() async {
    final caminhoBanco = join(await getDatabasesPath(), nomeArquivo);

    return openDatabase(
      caminhoBanco,
      version: _versaoSchema,
      onCreate: _criarSchema,
      onUpgrade: _atualizarSchema,
    );
  }

  Future<void> _criarSchema(Database db, int versao) async {
    await db.execute('''
      CREATE TABLE pesagens_locais (
        id_local INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        id_servidor INTEGER,
        bd TEXT NOT NULL,
        fazenda_id TEXT NOT NULL,
        epoca_id TEXT NOT NULL,
        lote TEXT NOT NULL,
        qtd_a_pesar INTEGER NOT NULL,
        qtd_pesados_servidor INTEGER,
        filtro_desc TEXT,
        usuario TEXT,
        criterios_lista TEXT,
        finalizada TEXT NOT NULL DEFAULT 'N',
        status_sync TEXT NOT NULL DEFAULT 'pendente',
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE itens_pesagem_locais (
        id_local INTEGER PRIMARY KEY AUTOINCREMENT,
        pesagem_id_local INTEGER NOT NULL,
        uuid TEXT NOT NULL UNIQUE,
        numero_item_local INTEGER NOT NULL,
        numero_item_servidor INTEGER,
        id_animal TEXT,
        codigo_animal TEXT,
        peso TEXT,
        ultimo_peso TEXT,
        sexo TEXT,
        nascimento TEXT,
        raca TEXT,
        pelagem TEXT,
        mae TEXT,
        obs TEXT,
        mens_repetido TEXT,
        id_pesagem_repetido TEXT,
        criterio_apartacao TEXT,
        status_sync TEXT NOT NULL DEFAULT 'pendente',
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        FOREIGN KEY (pesagem_id_local) REFERENCES pesagens_locais (id_local)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_itens_pesagem_id_local ON itens_pesagem_locais (pesagem_id_local)',
    );

    await db.execute('''
      CREATE TABLE outbox_sincronizacao (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tipo_operacao TEXT NOT NULL,
        entidade_uuid TEXT NOT NULL,
        depende_de_uuid TEXT,
        payload_json TEXT NOT NULL,
        tentativas INTEGER NOT NULL DEFAULT 0,
        proxima_tentativa_em TEXT,
        status TEXT NOT NULL DEFAULT 'pendente',
        ultimo_erro TEXT,
        criado_em TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_outbox_status ON outbox_sincronizacao (status)',
    );
    await db.execute(
      'CREATE INDEX idx_outbox_entidade ON outbox_sincronizacao (entidade_uuid)',
    );

    await db.execute('''
      CREATE TABLE animais_cache (
        id_animal TEXT PRIMARY KEY,
        fazenda_id TEXT NOT NULL,
        fazenda_nome TEXT,
        codigo TEXT,
        sexo TEXT,
        nascimento TEXT,
        raca TEXT,
        pelagem TEXT,
        id_mae TEXT,
        brinco_mae TEXT,
        ultimo_peso TEXT,
        data_ultimo_peso TEXT,
        lote_aberto TEXT,
        pesagem_id_lote_aberto TEXT,
        peso_desmama TEXT,
        ativo TEXT,
        atualizado_em TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_animais_cache_fazenda ON animais_cache (fazenda_id)',
    );
    await db.execute(
      'CREATE INDEX idx_animais_cache_mae ON animais_cache (id_mae)',
    );

    await _criarTabelaChuvaCache(db);
    await _criarTabelasMapaGado(db);
    await _criarTabelasMovimentacaoMapa(db);
    await _criarTabelasMapaSatelite(db);
    await _criarTabelaPesosMedios(db);
    await _criarTabelaExtrasMapa(db);
  }

  /// Dados avulsos do Mapa de Gado baixados junto com o tabuleiro, um JSON
  /// por chave: motivos de morte, animais em estação de monta e o tipo de
  /// controle de estoque da empresa (botão Morte da tela do pasto).
  Future<void> _criarTabelaExtrasMapa(Database db) async {
    await db.execute('''
      CREATE TABLE mapa_extras_cache (
        bd TEXT NOT NULL,
        chave TEXT NOT NULL,
        valor TEXT,
        PRIMARY KEY (bd, chave)
      )
    ''');
  }

  Future<void> _criarTabelaPesosMedios(Database db) async {
    // Peso médio dos animais da fazenda por categoria + sexo (mesma conta de
    // funcao_kg_ha_pasto.php do web) — Lotação (Kg/Ha) da tela do pasto.
    await db.execute('''
      CREATE TABLE mapa_pesos_medios_cache (
        bd TEXT NOT NULL,
        fazenda_id INTEGER NOT NULL,
        categoria INTEGER NOT NULL,
        sexo TEXT NOT NULL,
        peso INTEGER NOT NULL,
        PRIMARY KEY (bd, fazenda_id, categoria, sexo)
      )
    ''');
  }

  Future<void> _criarTabelasMapaSatelite(Database db) async {
    // Mapa Satélite: GeoJSON dos pastos de cada fazenda (mesmo mapa do
    // Editor de Mapa do web) e a cor de cada módulo. "versao" é o md5 do
    // servidor — o GeoJSON só é baixado de novo quando muda.
    await db.execute('''
      CREATE TABLE mapa_satelite_cache (
        bd TEXT NOT NULL,
        fazenda_id INTEGER NOT NULL,
        versao TEXT NOT NULL,
        geojson TEXT,
        latitude REAL,
        longitude REAL,
        PRIMARY KEY (bd, fazenda_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE mapa_modulos_cache (
        bd TEXT NOT NULL,
        id INTEGER NOT NULL,
        cor TEXT NOT NULL,
        PRIMARY KEY (bd, id)
      )
    ''');
  }

  Future<void> _criarTabelasMovimentacaoMapa(Database db) async {
    // Opções de "Descrição do Lote" (tbl_descricao_lote_animais) para
    // montar a descrição ao mover animais, sem internet.
    await db.execute('''
      CREATE TABLE mapa_descricoes_lote_cache (
        bd TEXT NOT NULL,
        id INTEGER NOT NULL,
        descricao TEXT NOT NULL,
        PRIMARY KEY (bd, id)
      )
    ''');
    // Fila das ações feitas no Mapa de Gado (mover todos os animais, nova
    // descrição do lote) — isolada da fila da pesagem, mesmo motivo da
    // chuva. Cada ação já é aplicada no cache na hora; fica aqui até o
    // servidor confirmar. status: 'pendente' (aguardando envio) ou 'erro'
    // (servidor recusou — não é reenviada, fica para o usuário ver).
    await db.execute('''
      CREATE TABLE mapa_outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bd TEXT NOT NULL,
        uuid TEXT NOT NULL UNIQUE,
        tipo TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pendente',
        tentativas INTEGER NOT NULL DEFAULT 0,
        ultimo_erro TEXT,
        criado_em TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_mapa_outbox_status ON mapa_outbox (bd, status)',
    );
  }

  Future<void> _criarTabelasMapaGado(Database db) async {
    // Cache do Mapa de Gado (Tabuleiro) — somente leitura por enquanto,
    // baixado inteiro por fazenda (api/rest/mapa-gado/tabuleiro.php) e
    // substituído a cada download. Guarda os dados "crus" (pastos, animais
    // no pasto e faixas de categoria) em vez das contagens prontas: as
    // contagens dependem da idade do animal no dia, então são calculadas
    // na hora (ver MapaTabuleiroCalculo) e continuam certas offline.
    await db.execute('''
      CREATE TABLE mapa_categorias_cache (
        bd TEXT NOT NULL,
        id INTEGER NOT NULL,
        idade_de INTEGER NOT NULL,
        idade_ate INTEGER NOT NULL,
        PRIMARY KEY (bd, id)
      )
    ''');
    await db.execute('''
      CREATE TABLE mapa_pastos_cache (
        bd TEXT NOT NULL,
        id INTEGER NOT NULL,
        fazenda_id INTEGER NOT NULL,
        descricao TEXT NOT NULL,
        modulo INTEGER NOT NULL,
        capim TEXT,
        categorias TEXT,
        ordem INTEGER NOT NULL,
        descricao_lote TEXT,
        lotes_json TEXT,
        tabuleiro INTEGER NOT NULL DEFAULT 1,
        data_com_animais TEXT,
        data_sem_animais TEXT,
        area REAL,
        id_lote INTEGER,
        ano_lote INTEGER,
        PRIMARY KEY (bd, id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_mapa_pastos_fazenda ON mapa_pastos_cache (bd, fazenda_id)',
    );
    await db.execute('''
      CREATE TABLE mapa_animais_pasto_cache (
        bd TEXT NOT NULL,
        fazenda_id INTEGER NOT NULL,
        local INTEGER NOT NULL,
        numero_item INTEGER NOT NULL,
        pasto_id INTEGER NOT NULL,
        sexo TEXT,
        nascimento TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_mapa_animais_fazenda ON mapa_animais_pasto_cache (bd, fazenda_id)',
    );
    // Hora do último download bem-sucedido de cada fazenda — exibida na
    // tela para o usuário saber de quando são os dados quando estiver
    // offline.
    await db.execute('''
      CREATE TABLE mapa_fazendas_cache (
        bd TEXT NOT NULL,
        fazenda_id INTEGER NOT NULL,
        atualizado_em TEXT NOT NULL,
        PRIMARY KEY (bd, fazenda_id)
      )
    ''');
  }

  Future<void> _criarTabelaChuvaCache(Database db) async {
    // Cache local do registro de chuva — mesmo papel de animais_cache, mas
    // com escrita: um lançamento feito em campo grava aqui primeiro
    // (sincronizado = 0) e só marca sincronizado = 1 depois que
    // ChuvaSyncService confirma com o servidor. A UNIQUE(bd, fazenda_id,
    // data) replica a regra do servidor (um registro por dia/fazenda, o
    // mais recente sobrescreve — ver ChuvaDao::createChuva no backend) e
    // permite usar INSERT ... OR REPLACE tanto para gravação local quanto
    // para atualizar com o que vem do servidor.
    await db.execute('''
      CREATE TABLE chuva_cache (
        id_local INTEGER PRIMARY KEY AUTOINCREMENT,
        bd TEXT NOT NULL,
        fazenda_id TEXT NOT NULL,
        data TEXT NOT NULL,
        volume REAL NOT NULL DEFAULT 0,
        id_servidor INTEGER,
        usuario TEXT,
        sincronizado INTEGER NOT NULL DEFAULT 1,
        atualizado_em TEXT NOT NULL,
        UNIQUE (bd, fazenda_id, data)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_chuva_cache_fazenda ON chuva_cache (bd, fazenda_id)',
    );
    await db.execute(
      'CREATE INDEX idx_chuva_cache_sincronizado ON chuva_cache (bd, sincronizado)',
    );
  }

  Future<void> _atualizarSchema(
    Database db,
    int versaoAntiga,
    int versaoNova,
  ) async {
    if (versaoAntiga < 2) {
      // Nome da fazenda de cada animal cacheado — precisa pra "Consultar
      // Mãe" (busca em todas as fazendas do usuário) exibir de qual
      // fazenda é cada filho, sem depender de rede pra isso.
      await db.execute(
        'ALTER TABLE animais_cache ADD COLUMN fazenda_nome TEXT',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_animais_cache_mae ON animais_cache (id_mae)',
      );
    }
    if (versaoAntiga < 3) {
      // Peso de desmama — precisa pra saber se um bezerro já foi desmamado
      // (regra do alerta "mãe/bezerro com apartação em lote aberto").
      await db.execute(
        'ALTER TABLE animais_cache ADD COLUMN peso_desmama TEXT',
      );
    }
    if (versaoAntiga < 4) {
      // Total de animais pesados que o servidor já informa na própria
      // listagem (list_pendentes.php) — os ITENS de uma pesagem só são
      // baixados quando ela é aberta (lazy), então sem isso a lista offline
      // mostrava "Pesados: 0" pra qualquer pesagem cujos itens ainda não
      // tinham sido baixados neste aparelho, parecendo que os dados tinham
      // sumido quando na verdade nunca tinham chegado ainda.
      await db.execute(
        'ALTER TABLE pesagens_locais ADD COLUMN qtd_pesados_servidor INTEGER',
      );
    }
    if (versaoAntiga < 5) {
      // Cadastro de chuva (tela Chuva) — mesma tabela nova de quem instala
      // do zero, criada aqui só para quem já tinha o app instalado antes
      // desta versão.
      await _criarTabelaChuvaCache(db);
    }
    if (versaoAntiga < 6) {
      // Se o animal está ativo ou não (S/N) — precisa pra tirar da busca
      // de "Nº do Animal" (tela de pesagem) as fêmeas inativas que o cache
      // guarda só pra "Consultar Mãe" achar filhos ativos (ver
      // AnimalCacheService). Enquanto esta coluna estiver NULL (cache
      // baixado antes desta versão), buscarPorCodigo trata como ativo —
      // só passa a filtrar de verdade depois do próximo download completo
      // do cadastro (garantirCacheCompleto roda de novo a cada reabertura
      // do app).
      await db.execute('ALTER TABLE animais_cache ADD COLUMN ativo TEXT');
    }
    if (versaoAntiga < 7) {
      // Mapa de Gado (Tabuleiro) offline — mesmas tabelas novas de quem
      // instala do zero.
      await _criarTabelasMapaGado(db);
    }
    if (versaoAntiga < 8) {
      // Mover animais no Mapa de Gado: descrição do lote de cada pasto,
      // opções de descrição e a fila de ações offline. Quem veio da v7 já
      // tem mapa_pastos_cache sem as colunas novas (quem vem de antes da
      // v7 acabou de criar a tabela já com elas, acima).
      if (versaoAntiga >= 7) {
        await db.execute(
          'ALTER TABLE mapa_pastos_cache ADD COLUMN descricao_lote TEXT',
        );
        await db.execute(
          'ALTER TABLE mapa_pastos_cache ADD COLUMN lotes_json TEXT',
        );
      }
      await _criarTabelasMovimentacaoMapa(db);
    }
    if (versaoAntiga < 9) {
      // Mapa Satélite: pastos dos módulos 1006/1007 (só no satélite),
      // datas com/sem animais (balão de informações), GeoJSON e cores.
      // Quem vem de antes da v7 acabou de criar mapa_pastos_cache já com
      // as colunas novas (acima).
      if (versaoAntiga >= 7) {
        await db.execute(
          'ALTER TABLE mapa_pastos_cache ADD COLUMN tabuleiro INTEGER NOT NULL DEFAULT 1',
        );
        await db.execute(
          'ALTER TABLE mapa_pastos_cache ADD COLUMN data_com_animais TEXT',
        );
        await db.execute(
          'ALTER TABLE mapa_pastos_cache ADD COLUMN data_sem_animais TEXT',
        );
      }
      await _criarTabelasMapaSatelite(db);
    }
    if (versaoAntiga < 10) {
      // Tela do pasto: área (Lotação Kg/Ha), número/ano do lote
      // ("L-0012/26") e pesos médios por categoria/sexo.
      if (versaoAntiga >= 7) {
        await db.execute('ALTER TABLE mapa_pastos_cache ADD COLUMN area REAL');
        await db.execute(
          'ALTER TABLE mapa_pastos_cache ADD COLUMN id_lote INTEGER',
        );
        await db.execute(
          'ALTER TABLE mapa_pastos_cache ADD COLUMN ano_lote INTEGER',
        );
      }
      await _criarTabelaPesosMedios(db);
    }
    if (versaoAntiga < 11) {
      await _criarTabelaExtrasMapa(db);
    }
  }

  /// Só para os testes/roteiro de verificação manual — apaga todos os dados
  /// locais (não usado em nenhum fluxo de tela).
  Future<void> resetarParaTeste() async {
    final db = await database;
    await db.delete('outbox_sincronizacao');
    await db.delete('itens_pesagem_locais');
    await db.delete('pesagens_locais');
    await db.delete('animais_cache');
    await db.delete('chuva_cache');
    await db.delete('mapa_categorias_cache');
    await db.delete('mapa_pastos_cache');
    await db.delete('mapa_animais_pasto_cache');
    await db.delete('mapa_fazendas_cache');
    await db.delete('mapa_descricoes_lote_cache');
    await db.delete('mapa_outbox');
    await db.delete('mapa_satelite_cache');
    await db.delete('mapa_modulos_cache');
    await db.delete('mapa_pesos_medios_cache');
    await db.delete('mapa_extras_cache');
  }
}
