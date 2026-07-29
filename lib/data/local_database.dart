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

  static const int _versaoSchema = 3;

  Database? _db;

  Future<Database> get database async {
    _db ??= await _abrir();
    return _db!;
  }

  Future<Database> _abrir() async {
    final caminhoBanco = join(await getDatabasesPath(), 'boivirtual_offline.db');

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
        atualizado_em TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_animais_cache_fazenda ON animais_cache (fazenda_id)',
    );
    await db.execute(
      'CREATE INDEX idx_animais_cache_mae ON animais_cache (id_mae)',
    );
  }

  Future<void> _atualizarSchema(Database db, int versaoAntiga, int versaoNova) async {
    if (versaoAntiga < 2) {
      // Nome da fazenda de cada animal cacheado — precisa pra "Consultar
      // Mãe" (busca em todas as fazendas do usuário) exibir de qual
      // fazenda é cada filho, sem depender de rede pra isso.
      await db.execute('ALTER TABLE animais_cache ADD COLUMN fazenda_nome TEXT');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_animais_cache_mae ON animais_cache (id_mae)',
      );
    }
    if (versaoAntiga < 3) {
      // Peso de desmama — precisa pra saber se um bezerro já foi desmamado
      // (regra do alerta "mãe/bezerro com apartação em lote aberto").
      await db.execute('ALTER TABLE animais_cache ADD COLUMN peso_desmama TEXT');
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
  }
}
