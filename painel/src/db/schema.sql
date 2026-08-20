-- ============================================================================
-- Painel Backup CH.Com — estrutura do banco
--
-- Banco: SQLite no MVP. O objetivo declarado é migrar para PostgreSQL depois,
-- então este arquivo evita de propósito o que é exclusivo do SQLite:
--
--   * datas gravadas como TEXTO em ISO 8601 UTC ("2026-08-12T19:30:00.000Z"),
--     não como número. SQLite não tem tipo de data; texto ISO ordena
--     corretamente com comparação alfabética e é lido igual no Postgres.
--   * INTEGER PRIMARY KEY sem AUTOINCREMENT. No SQLite isso já numera
--     sozinho; no Postgres vira BIGINT GENERATED ALWAYS AS IDENTITY trocando
--     uma linha.
--   * nenhum tipo exótico, nenhuma função específica de fornecedor.
--
-- Tudo é IF NOT EXISTS: rodar a migração de novo não quebra nada.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- CLIENTES — um por cartório
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS clientes (
    id          INTEGER PRIMARY KEY,

    nome        TEXT    NOT NULL,
    cidade      TEXT    NOT NULL,

    -- O token vai na URL que o Duplicati daquele cartório chama:
    --   POST /api/report/{token}
    -- É o que identifica de quem veio o relatório. UNIQUE porque dois
    -- cartórios com o mesmo token tornariam impossível saber a origem.
    token       TEXT    NOT NULL UNIQUE,

    -- Desativar um cliente faz o endpoint recusar os relatórios dele sem
    -- precisar apagar o histórico já recebido.
    ativo       INTEGER NOT NULL DEFAULT 1,

    criado_em   TEXT    NOT NULL
);


-- ----------------------------------------------------------------------------
-- RELATÓRIOS — um por execução de backup que o Duplicati reportar
--
-- Guardamos DUAS representações do mesmo relatório de propósito:
--
--   1. json_bruto  — o corpo inteiro do POST, exatamente como chegou.
--   2. as colunas  — os campos que já sabemos ler, extraídos.
--
-- O JSON bruto é a rede de segurança: se amanhã descobrirmos um campo novo,
-- ou se o parser estiver lendo algo errado, dá para reprocessar todo o
-- histórico sem ter perdido nada. Extrair sem guardar o original seria uma
-- decisão irreversível tomada antes de conhecer bem os dados.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS relatorios (
    id                  INTEGER PRIMARY KEY,

    cliente_id          INTEGER NOT NULL REFERENCES clientes(id),

    -- Quando o painel recebeu. Não confundir com fim_em, que é quando o
    -- backup terminou na máquina do cartório: os relógios podem divergir e
    -- um relatório pode chegar atrasado.
    recebido_em         TEXT    NOT NULL,

    -- ---- campos extraídos do JSON do Duplicati -----------------------------
    -- Todos aceitam NULL. Um relatório de erro grave pode vir sem métricas,
    -- e é melhor gravar o que veio do que recusar o relatório inteiro.

    -- Data.ParsedResult -> Success | Warning | Error | Fatal | Unknown
    resultado           TEXT,

    -- Data.MainOperation -> Backup, Restore, Test, Delete...
    operacao            TEXT,

    -- Data.BeginTime / Data.EndTime, normalizados para ISO 8601 UTC
    inicio_em           TEXT,
    fim_em              TEXT,

    -- Data.Duration ("00:04:12.3456789") convertida para segundos, que é o
    -- formato que serve tanto para exibir quanto para somar e comparar.
    duracao_segundos    INTEGER,

    -- Data.SizeOfExaminedFiles — tamanho total da origem examinada
    tamanho_origem      INTEGER,

    -- Data.SizeOfAddedFiles — quanto entrou de novo nesta execução.
    -- Junto com bytes_enviados, é o "tamanho desta versão do backup",
    -- que é o recurso central do produto.
    tamanho_adicionado  INTEGER,

    -- Data.BackendStatistics.BytesUploaded — quanto subiu para o S3 agora
    bytes_enviados      INTEGER,

    -- Data.BackendStatistics.KnownFileSize — total acumulado no destino
    tamanho_destino     INTEGER,

    -- Data.WarningsActualLength / Data.ErrorsActualLength
    qtd_avisos          INTEGER,
    qtd_erros           INTEGER,

    -- Extra.backup-name e Extra.machine-name.
    --
    -- Descobertos ao calibrar contra um Duplicati real, e importam mais do
    -- que parecem: um cartório pode ter VÁRIOS backups configurados (base do
    -- sistema, arquivos digitalizados, etc.), e todos usam o mesmo token.
    -- Sem estes campos, execuções de backups diferentes ficariam empilhadas
    -- no mesmo histórico como se fossem versões de uma coisa só, e o
    -- "tamanho por versão" passaria a comparar coisas distintas.
    backup_nome         TEXT,
    maquina_nome        TEXT,

    -- ---- a rede de segurança -----------------------------------------------
    json_bruto          TEXT    NOT NULL,

    -- Versão do parser que preencheu as colunas acima. Serve para saber
    -- quais linhas precisam ser reprocessadas quando o parser mudar.
    versao_parser       INTEGER NOT NULL DEFAULT 1
);

-- O painel pergunta "qual o último relatório deste cartório?" a cada
-- carregamento de tela. Sem este índice isso vira varredura da tabela
-- inteira, o que degrada conforme o histórico cresce.
CREATE INDEX IF NOT EXISTS idx_relatorios_cliente_recebido
    ON relatorios (cliente_id, recebido_em DESC);


-- ----------------------------------------------------------------------------
-- RECEBIMENTOS RECUSADOS — o diário de bordo do que não entrou
--
-- Quando um POST chega com token inválido, ou com corpo que não é JSON, não
-- dá para gravar em relatorios (não se sabe de qual cliente é). Sem registrar
-- em lugar nenhum, um cartório configurado com o token errado ficaria
-- silenciosamente sem reportar, e o painel o mostraria como "nunca reportou"
-- sem nenhuma pista do motivo. Esta tabela é essa pista.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS recebimentos_recusados (
    id           INTEGER PRIMARY KEY,
    recebido_em  TEXT    NOT NULL,
    token_usado  TEXT,
    motivo       TEXT    NOT NULL,
    ip_origem    TEXT,
    corpo_bruto  TEXT
);

CREATE INDEX IF NOT EXISTS idx_recusados_recebido
    ON recebimentos_recusados (recebido_em DESC);


-- ----------------------------------------------------------------------------
-- ADMINS — quem pode abrir o painel
--
-- No MVP é um usuário só, mas a tabela já é uma tabela, e não uma senha solta
-- num arquivo de configuração: criar mais usuários depois vira INSERT, e a
-- coluna de papel (admin/visualizador) que está prevista para o futuro entra
-- sem migração de estrutura.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS admins (
    id            INTEGER PRIMARY KEY,
    usuario       TEXT    NOT NULL UNIQUE,

    -- NUNCA a senha. Guardamos o hash scrypt e o sal usado para calculá-lo.
    -- Se este banco vazar, as senhas continuam protegidas.
    senha_hash    TEXT    NOT NULL,
    senha_sal     TEXT    NOT NULL,

    criado_em     TEXT    NOT NULL,
    ultimo_acesso TEXT
);


-- ----------------------------------------------------------------------------
-- SESSÕES — quem está logado agora
--
-- As sessões ficam no banco, não na memória do processo. Assim reiniciar o
-- painel (ou o container) não desloga todo mundo, e dá para encerrar uma
-- sessão específica apagando a linha — o que um cookie autoassinado sem
-- estado não permitiria.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sessoes (
    -- O identificador é o próprio valor aleatório do cookie.
    id         TEXT    PRIMARY KEY,
    admin_id   INTEGER NOT NULL REFERENCES admins(id),
    criada_em  TEXT    NOT NULL,
    expira_em  TEXT    NOT NULL,
    ip_origem  TEXT
);

CREATE INDEX IF NOT EXISTS idx_sessoes_expira ON sessoes (expira_em);
