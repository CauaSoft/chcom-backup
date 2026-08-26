import crypto from 'node:crypto';
import { db, agoraISO } from './index';
import type { CamposExtraidos } from '../duplicati/parse';

/**
 * Todo o acesso ao banco fica aqui, num lugar só.
 *
 * O resto do código nunca escreve SQL. Quando migrarmos para PostgreSQL, é
 * este arquivo que muda — as rotas e o parser não sabem qual banco existe do
 * outro lado, então não precisam ser tocados.
 */

export interface Cliente {
  id: number;
  nome: string;
  cidade: string;
  token: string;
  ativo: number;
  criado_em: string;
}

/**
 * Gera o token que vai na URL do Duplicati.
 *
 * 32 caracteres hexadecimais = 128 bits de aleatoriedade criptográfica. Como
 * o token é a única coisa que autentica o cartório no endpoint, ele precisa
 * ser impossível de adivinhar — `Math.random()` não serve aqui, porque é
 * previsível a partir de saídas anteriores.
 */
export function gerarToken(): string {
  return crypto.randomBytes(16).toString('hex');
}

export function criarCliente(nome: string, cidade: string): Cliente {
  const token = gerarToken();
  const info = db()
    .prepare(
      `INSERT INTO clientes (nome, cidade, token, ativo, criado_em)
       VALUES (?, ?, ?, 1, ?)`,
    )
    .run(nome, cidade, token, agoraISO());

  return buscarClientePorId(Number(info.lastInsertRowid))!;
}

export function buscarClientePorId(id: number): Cliente | undefined {
  return db().prepare('SELECT * FROM clientes WHERE id = ?').get(id) as
    | Cliente
    | undefined;
}

export function buscarClientePorToken(token: string): Cliente | undefined {
  return db().prepare('SELECT * FROM clientes WHERE token = ?').get(token) as
    | Cliente
    | undefined;
}

export function listarClientes(): Cliente[] {
  return db()
    .prepare('SELECT * FROM clientes ORDER BY nome')
    .all() as Cliente[];
}

export interface ClienteCadastro extends Cliente {
  total_relatorios: number;
  ultimo_em: string | null;
}

/**
 * A lista do cadastro, já com o sinal de vida de cada cartório.
 *
 * Depois de cadastrar um cartório e configurar o Duplicati dele, a pergunta
 * imediata é "funcionou?". Sem isto era preciso sair desta tela, ir ao painel
 * e procurar o nome na lista — e voltar. O dado custa uma subconsulta.
 */
export function listarClientesComSinal(): ClienteCadastro[] {
  return db()
    .prepare(
      `SELECT c.*,
              (SELECT COUNT(*) FROM relatorios WHERE cliente_id = c.id) AS total_relatorios,
              (SELECT COALESCE(fim_em, recebido_em) FROM relatorios
                WHERE cliente_id = c.id
                ORDER BY recebido_em DESC, id DESC LIMIT 1) AS ultimo_em
         FROM clientes c
        ORDER BY c.nome`,
    )
    .all() as ClienteCadastro[];
}

/**
 * Corrige nome e cidade. NÃO mexe no token: trocar o token aqui quebraria o
 * Duplicati do cartório sem aviso, e arrumar um erro de digitação não pode
 * ter esse efeito.
 */
export function atualizarCliente(id: number, nome: string, cidade: string): void {
  db()
    .prepare('UPDATE clientes SET nome = ?, cidade = ? WHERE id = ?')
    .run(nome, cidade, id);
}

/**
 * Gera um token novo para o cartório e devolve o novo.
 *
 * O antigo para de funcionar na hora — é esse o ponto: serve para quando o
 * token vazou. Mas isso significa que o Duplicati daquele cartório para de
 * reportar até alguém colar a URL nova lá. A tela precisa deixar isso claro
 * antes, porque o efeito só aparece no dia seguinte, quando o backup roda.
 */
export function regerarToken(id: number): string {
  const token = gerarToken();
  db().prepare('UPDATE clientes SET token = ? WHERE id = ?').run(token, id);
  return token;
}

export function salvarRelatorio(
  clienteId: number,
  campos: CamposExtraidos,
  jsonBruto: string,
  versaoParser: number,
  /**
   * Quando o painel recebeu. Só é passado explicitamente pelo gerador de
   * dados de demonstração, que precisa criar histórico com datas no passado.
   * Em uso normal fica de fora e vale o instante atual.
   */
  recebidoEm?: string,
): number {
  const info = db()
    .prepare(
      `INSERT INTO relatorios (
         cliente_id, recebido_em,
         resultado, operacao, inicio_em, fim_em, duracao_segundos,
         tamanho_origem, tamanho_adicionado, bytes_enviados, tamanho_destino,
         qtd_avisos, qtd_erros, backup_nome, maquina_nome,
         json_bruto, versao_parser
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .run(
      clienteId,
      recebidoEm ?? agoraISO(),
      campos.resultado,
      campos.operacao,
      campos.inicioEm,
      campos.fimEm,
      campos.duracaoSegundos,
      campos.tamanhoOrigem,
      campos.tamanhoAdicionado,
      campos.bytesEnviados,
      campos.tamanhoDestino,
      campos.qtdAvisos,
      campos.qtdErros,
      campos.backupNome,
      campos.maquinaNome,
      jsonBruto,
      versaoParser,
    );

  return Number(info.lastInsertRowid);
}

// ---------------------------------------------------------------------------
// ADMINS E SESSÕES
// ---------------------------------------------------------------------------

export interface Admin {
  id: number;
  usuario: string;
  senha_hash: string;
  senha_sal: string;
  criado_em: string;
  ultimo_acesso: string | null;
}

export function buscarAdmin(usuario: string): Admin | undefined {
  return db().prepare('SELECT * FROM admins WHERE usuario = ?').get(usuario) as
    | Admin
    | undefined;
}

export function contarAdmins(): number {
  const { n } = db().prepare('SELECT COUNT(*) AS n FROM admins').get() as {
    n: number;
  };
  return n;
}

/** Cria o admin, ou troca a senha se o usuário já existir. */
export function definirAdmin(
  usuario: string,
  hash: string,
  sal: string,
): void {
  const existente = buscarAdmin(usuario);
  if (existente) {
    db()
      .prepare('UPDATE admins SET senha_hash = ?, senha_sal = ? WHERE id = ?')
      .run(hash, sal, existente.id);
    // Trocar a senha derruba as sessões abertas. Se a troca aconteceu porque
    // a senha vazou, manter as sessões vivas anularia o motivo da troca.
    db().prepare('DELETE FROM sessoes WHERE admin_id = ?').run(existente.id);
    return;
  }

  db()
    .prepare(
      `INSERT INTO admins (usuario, senha_hash, senha_sal, criado_em)
       VALUES (?, ?, ?, ?)`,
    )
    .run(usuario, hash, sal, agoraISO());
}

export function marcarAcesso(adminId: number): void {
  db()
    .prepare('UPDATE admins SET ultimo_acesso = ? WHERE id = ?')
    .run(agoraISO(), adminId);
}

export function criarSessao(
  id: string,
  adminId: number,
  expiraEm: string,
  ip: string | null,
): void {
  db()
    .prepare(
      `INSERT INTO sessoes (id, admin_id, criada_em, expira_em, ip_origem)
       VALUES (?, ?, ?, ?, ?)`,
    )
    .run(id, adminId, agoraISO(), expiraEm, ip);
}

export interface SessaoComAdmin {
  admin_id: number;
  usuario: string;
  expira_em: string;
}

export function buscarSessao(id: string): SessaoComAdmin | undefined {
  return db()
    .prepare(
      `SELECT s.admin_id, s.expira_em, a.usuario
         FROM sessoes s
         JOIN admins a ON a.id = s.admin_id
        WHERE s.id = ? AND s.expira_em > ?`,
    )
    .get(id, agoraISO()) as SessaoComAdmin | undefined;
}

export function apagarSessao(id: string): void {
  db().prepare('DELETE FROM sessoes WHERE id = ?').run(id);
}

/**
 * Remove sessões vencidas. Sem isso a tabela cresceria para sempre, guardando
 * linhas que já não autenticam ninguém.
 */
export function limparSessoesVencidas(): number {
  const info = db().prepare('DELETE FROM sessoes WHERE expira_em <= ?').run(agoraISO());
  return info.changes;
}

// ---------------------------------------------------------------------------

export function definirAtivoCliente(id: number, ativo: boolean): void {
  db().prepare('UPDATE clientes SET ativo = ? WHERE id = ?').run(ativo ? 1 : 0, id);
}

/**
 * Apaga um cartório e TODO o histórico dele.
 *
 * Não tem volta. Os relatórios são apagados junto porque uma linha de
 * relatório sem cartório não serve para nada e ainda segura o registro do
 * token no banco.
 *
 * Numa transação: apagar os relatórios e falhar ao apagar o cartório deixaria
 * um cartório vazio no painel, e o contrário deixaria relatórios órfãos que
 * nenhuma tela mostra e ninguém mais consegue limpar.
 *
 * Devolve quantos relatórios foram apagados, para a tela poder dizer o que
 * de fato se perdeu.
 */
export function excluirCliente(id: number): number {
  const banco = db();
  const apagar = banco.transaction((idCliente: number) => {
    const r = banco
      .prepare('DELETE FROM relatorios WHERE cliente_id = ?')
      .run(idCliente);
    banco.prepare('DELETE FROM clientes WHERE id = ?').run(idCliente);
    return r.changes;
  });
  return apagar(id) as number;
}

export function registrarRecusa(opcoes: {
  tokenUsado: string | null;
  motivo: string;
  ipOrigem: string | null;
  corpoBruto: string | null;
}): void {
  // O corpo é cortado antes de gravar: uma recusa por "corpo gigante" não
  // deve ser justamente o que enche o disco.
  const corpo = opcoes.corpoBruto ? opcoes.corpoBruto.slice(0, 10_000) : null;

  db()
    .prepare(
      `INSERT INTO recebimentos_recusados
         (recebido_em, token_usado, motivo, ip_origem, corpo_bruto)
       VALUES (?, ?, ?, ?, ?)`,
    )
    .run(agoraISO(), opcoes.tokenUsado, opcoes.motivo, opcoes.ipOrigem, corpo);
}

export interface LinhaPainel {
  id: number;
  nome: string;
  cidade: string;
  ativo: number;
  total_relatorios: number;
  // Vindos do último relatório. Todos NULL se o cartório nunca reportou.
  resultado: string | null;
  recebido_em: string | null;
  fim_em: string | null;
  duracao_segundos: number | null;
  tamanho_origem: number | null;
  tamanho_destino: number | null;
  tamanho_adicionado: number | null;
  bytes_enviados: number | null;
  qtd_avisos: number | null;
  qtd_erros: number | null;
  /** Último tamanho de destino REAL, que pode não ser o do último relatório. */
  destino_conhecido: number | null;
  origem_conhecida: number | null;
}

/**
 * Uma linha por cartório, já com os dados do ÚLTIMO relatório dele.
 *
 * O LEFT JOIN contra uma subconsulta que devolve um único id é o que faz
 * cartórios sem nenhum relatório continuarem aparecendo na lista, com os
 * campos vazios. Um INNER JOIN os esconderia — e um cartório que nunca
 * reportou é justamente o que mais precisa ser visto.
 *
 * O desempate por `id DESC` importa: dois relatórios podem cair no mesmo
 * milissegundo de `recebido_em`, e sem o desempate a linha escolhida seria
 * imprevisível.
 */
export function resumoPainel(): LinhaPainel[] {
  return db()
    .prepare(
      `SELECT
         c.id, c.nome, c.cidade, c.ativo,
         (SELECT COUNT(*) FROM relatorios WHERE cliente_id = c.id) AS total_relatorios,
         r.resultado, r.recebido_em, r.fim_em, r.duracao_segundos,
         r.tamanho_origem, r.tamanho_destino, r.tamanho_adicionado,
         r.bytes_enviados, r.qtd_avisos, r.qtd_erros,

         -- Último tamanho REAL medido, que nem sempre é o do último
         -- relatório: quando o backup falha antes de listar o destino, o
         -- Duplicati manda 0. Mostrar esse 0 faria parecer que o backup
         -- sumiu da nuvem, quando o que falhou foi só a execução de hoje.
         -- Comportamento observado num backup real, não suposto.
         (SELECT tamanho_destino FROM relatorios
           WHERE cliente_id = c.id AND tamanho_destino > 0
           ORDER BY recebido_em DESC, id DESC LIMIT 1) AS destino_conhecido,
         (SELECT tamanho_origem FROM relatorios
           WHERE cliente_id = c.id AND tamanho_origem > 0
           ORDER BY recebido_em DESC, id DESC LIMIT 1) AS origem_conhecida
       FROM clientes c
       LEFT JOIN relatorios r
         ON r.id = (
              SELECT id FROM relatorios
               WHERE cliente_id = c.id
               ORDER BY recebido_em DESC, id DESC
               LIMIT 1
            )
       ORDER BY c.nome`,
    )
    .all() as LinhaPainel[];
}

export interface DiaResumo {
  dia: string;
  ok: number;
  aviso: number;
  erro: number;
  enviado: number;
}

/**
 * Um resumo por dia de TODOS os cartórios juntos, para os gráficos do painel.
 *
 * Responde as duas perguntas que a lista não responde:
 *   - "quantos backups rodaram ontem, e quantos falharam?"
 *   - "quanto de dado subiu por dia?"
 *
 * A agregação é feita no banco, não em JavaScript: com 100 cartórios rodando
 * todo dia, trazer 3.000 linhas para o Node contar seria desperdício de
 * memória e de tempo a cada carregamento da tela.
 *
 * Usa fim_em quando existe e recebido_em quando não — um relatório pode
 * chegar depois da meia-noite e cair no dia errado se for pela hora de
 * chegada.
 */
export function resumoPorDia(dias = 30): DiaResumo[] {
  return db()
    .prepare(
      `SELECT date(COALESCE(fim_em, recebido_em)) AS dia,
              SUM(CASE WHEN lower(COALESCE(resultado,'')) = 'success' THEN 1 ELSE 0 END) AS ok,
              SUM(CASE WHEN lower(COALESCE(resultado,'')) = 'warning' THEN 1 ELSE 0 END) AS aviso,
              SUM(CASE WHEN lower(COALESCE(resultado,'')) IN ('error','fatal') THEN 1 ELSE 0 END) AS erro,
              COALESCE(SUM(bytes_enviados), 0) AS enviado
         FROM relatorios
        WHERE date(COALESCE(fim_em, recebido_em)) >= date('now', ?)
        GROUP BY dia
        ORDER BY dia ASC`,
    )
    .all(`-${dias} days`) as DiaResumo[];
}

export interface PontoMini {
  cliente_id: number;
  bytes_enviados: number | null;
  resultado: string | null;
  fim_em: string | null;
  recebido_em: string;
}

/**
 * As últimas N execuções de CADA cartório, numa consulta só.
 *
 * Serve ao minigráfico da tela principal. Sem isto, a lista mostra apenas o
 * estado do último backup, e um cartório que vem falhando dia sim dia não
 * fica idêntico a um que nunca falhou — a única diferença aparece quando se
 * abre o histórico dele, um por um.
 *
 * Uma consulta com janela em vez de N consultas: com 100 cartórios, o laço
 * seriam 100 idas ao banco a cada carregamento da tela.
 */
export function ultimasExecucoesDeTodos(limite = 12): Map<number, PontoMini[]> {
  const linhas = db()
    .prepare(
      `SELECT cliente_id, bytes_enviados, resultado, fim_em, recebido_em
         FROM (
           SELECT cliente_id, bytes_enviados, resultado, fim_em, recebido_em,
                  ROW_NUMBER() OVER (
                    PARTITION BY cliente_id
                    ORDER BY recebido_em DESC, id DESC
                  ) AS posicao
             FROM relatorios
         )
        WHERE posicao <= ?
        ORDER BY cliente_id, recebido_em ASC`,
    )
    .all(limite) as PontoMini[];

  const mapa = new Map<number, PontoMini[]>();
  for (const l of linhas) {
    const atual = mapa.get(l.cliente_id);
    if (atual) atual.push(l);
    else mapa.set(l.cliente_id, [l]);
  }
  return mapa;
}

export interface MensagensDoRelatorio {
  erros: string[];
  avisos: string[];
}

/**
 * O texto do que deu errado, para as execuções indicadas.
 *
 * As mensagens não têm coluna própria: vêm de dentro do json_bruto, que
 * guarda o relatório inteiro como o Duplicati mandou. Extrair na hora evita
 * uma migração de banco e não perde nada — o dado sempre esteve ali.
 *
 * Só busca os relatórios PEDIDOS, nunca todos. Um json_bruto pode ter vários
 * MB quando o backup encontrou milhares de arquivos travados; carregar os 45
 * de um cartório para mostrar duas mensagens seria caro à toa.
 */
export function mensagensDosRelatorios(ids: number[]): Map<number, MensagensDoRelatorio> {
  const mapa = new Map<number, MensagensDoRelatorio>();
  if (ids.length === 0) return mapa;

  const marcadores = ids.map(() => '?').join(',');
  const linhas = db()
    .prepare(`SELECT id, json_bruto FROM relatorios WHERE id IN (${marcadores})`)
    .all(...ids) as { id: number; json_bruto: string }[];

  for (const l of linhas) {
    let bruto: unknown;
    try {
      bruto = JSON.parse(l.json_bruto);
    } catch {
      continue; // relatório ilegível não pode derrubar a tela
    }
    const raiz = bruto as Record<string, unknown>;
    const dados = (raiz?.Data ?? raiz) as Record<string, unknown>;

    mapa.set(l.id, {
      erros: limparLista(dados?.Errors),
      avisos: limparLista(dados?.Warnings),
    });
  }
  return mapa;
}

/** Normaliza a lista de mensagens: sem vazias, sem repetidas, no máximo 12. */
function limparLista(valor: unknown): string[] {
  if (!Array.isArray(valor)) return [];
  const saida: string[] = [];
  for (const item of valor) {
    const texto = String(item ?? '')
      .replace(/\s+/g, ' ')
      .trim();
    if (texto && !saida.includes(texto)) saida.push(texto);
    if (saida.length >= 12) break;
  }
  return saida;
}

export interface LinhaHistorico {
  id: number;
  recebido_em: string;
  resultado: string | null;
  operacao: string | null;
  backup_nome: string | null;
  maquina_nome: string | null;
  inicio_em: string | null;
  fim_em: string | null;
  duracao_segundos: number | null;
  tamanho_origem: number | null;
  tamanho_adicionado: number | null;
  bytes_enviados: number | null;
  tamanho_destino: number | null;
  qtd_avisos: number | null;
  qtd_erros: number | null;
}

/**
 * O histórico de execuções de um cartório, do mais recente para o mais
 * antigo. Uma linha por versão de backup — é a tela principal do produto.
 */
export function historicoDoCliente(
  clienteId: number,
  limite = 200,
): LinhaHistorico[] {
  return db()
    .prepare(
      `SELECT id, recebido_em, resultado, operacao, inicio_em, fim_em,
              duracao_segundos, tamanho_origem, tamanho_adicionado,
              bytes_enviados, tamanho_destino, qtd_avisos, qtd_erros,
              backup_nome, maquina_nome
         FROM relatorios
        WHERE cliente_id = ?
        ORDER BY recebido_em DESC, id DESC
        LIMIT ?`,
    )
    .all(clienteId, limite) as LinhaHistorico[];
}

/** Os N relatórios mais recentes, de todos os clientes. Usado na calibração. */
export function ultimosRelatorios(limite = 20) {
  return db()
    .prepare(
      `SELECT r.*, c.nome AS cliente_nome, c.cidade AS cliente_cidade
         FROM relatorios r
         JOIN clientes c ON c.id = r.cliente_id
        ORDER BY r.recebido_em DESC
        LIMIT ?`,
    )
    .all(limite) as Array<Record<string, unknown>>;
}

export function ultimasRecusas(limite = 20) {
  return db()
    .prepare(
      `SELECT * FROM recebimentos_recusados ORDER BY recebido_em DESC LIMIT ?`,
    )
    .all(limite) as Array<Record<string, unknown>>;
}

// ============================================================================
//  CH.Com Cofre — a cópia externa para desastre
// ============================================================================

/** Um item protegido dentro de uma execução do Cofre. */
export interface ItemDoCofre {
  tipo: string;
  nome: string;
  sucesso: boolean;
  consistencia: string | null;
  bytes: number;
  quando: string | null;
}

export interface ExecucaoDoCofre {
  maquina: string;
  comecouEm: string | null;
  terminouEm: string | null;
  resultado: string | null;
  itens: number;
  sucessos: number;
  falhas: number;
  detalhes: ItemDoCofre[];
}

/**
 * Grava uma execução do Cofre com todos os seus itens.
 *
 * Em transação, e isso não é detalhe: uma execução gravada sem os itens
 * apareceria no painel como "sucesso, 3 itens" com a lista vazia — pior que
 * não aparecer, porque parece completa. Ou grava tudo, ou nada.
 */
export function salvarExecucaoDoCofre(
  clienteId: number,
  execucao: ExecucaoDoCofre,
  jsonBruto: string,
  versao: number,
  recebidoEm?: string,
): number {
  const gravar = db().transaction(() => {
    const info = db()
      .prepare(
        `INSERT INTO cofre_execucoes (
           cliente_id, maquina, recebido_em, comecou_em, terminou_em,
           resultado, itens, sucessos, falhas, json_bruto, versao
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(
        clienteId,
        execucao.maquina,
        recebidoEm ?? agoraISO(),
        execucao.comecouEm,
        execucao.terminouEm,
        execucao.resultado,
        execucao.itens,
        execucao.sucessos,
        execucao.falhas,
        jsonBruto,
        versao,
      );

    const execucaoId = Number(info.lastInsertRowid);

    const inserirItem = db().prepare(
      `INSERT INTO cofre_itens
         (execucao_id, tipo, nome, sucesso, consistencia, bytes, quando)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
    );
    for (const item of execucao.detalhes) {
      inserirItem.run(
        execucaoId,
        item.tipo,
        item.nome,
        item.sucesso ? 1 : 0,
        item.consistencia,
        item.bytes,
        item.quando,
      );
    }

    return execucaoId;
  });

  return gravar();
}

/**
 * A última vez que CADA item subiu com sucesso, por cliente.
 *
 * É o que responde a pergunta que importa no painel: não "o último backup deu
 * certo?", e sim "há quanto tempo esta VM não sobe?". Uma execução recente
 * bem-sucedida pode não ter tocado numa VM que está parada há três meses —
 * e é exatamente esse tipo de buraco que passa despercebido.
 *
 * A função de janela numera as linhas de cada item pela data, do mais recente
 * para o mais antigo, e ficamos só com a primeira de cada.
 */
export function ultimoSucessoPorItem(clienteId: number): Array<{
  tipo: string;
  nome: string;
  maquina: string;
  consistencia: string | null;
  bytes: number;
  quando: string | null;
}> {
  return db()
    .prepare(
      `SELECT tipo, nome, maquina, consistencia, bytes, quando FROM (
         SELECT i.tipo, i.nome, e.maquina, i.consistencia, i.bytes, i.quando,
                ROW_NUMBER() OVER (
                  PARTITION BY e.maquina, i.tipo, i.nome
                  ORDER BY i.quando DESC
                ) AS posicao
           FROM cofre_itens i
           JOIN cofre_execucoes e ON e.id = i.execucao_id
          WHERE e.cliente_id = ? AND i.sucesso = 1
       ) WHERE posicao = 1
       ORDER BY maquina, tipo, nome`,
    )
    .all(clienteId) as Array<{
    tipo: string;
    nome: string;
    maquina: string;
    consistencia: string | null;
    bytes: number;
    quando: string | null;
  }>;
}

/** As execuções mais recentes do Cofre de um cliente. */
export function execucoesDoCofre(clienteId: number, limite = 30) {
  return db()
    .prepare(
      `SELECT id, maquina, recebido_em, comecou_em, terminou_em,
              resultado, itens, sucessos, falhas
         FROM cofre_execucoes
        WHERE cliente_id = ?
        ORDER BY recebido_em DESC
        LIMIT ?`,
    )
    .all(clienteId, limite);
}

/** Os itens de uma execução. */
export function itensDaExecucao(execucaoId: number) {
  return db()
    .prepare(
      `SELECT tipo, nome, sucesso, consistencia, bytes, quando
         FROM cofre_itens
        WHERE execucao_id = ?
        ORDER BY sucesso ASC, tipo, nome`,
    )
    .all(execucaoId);
}
