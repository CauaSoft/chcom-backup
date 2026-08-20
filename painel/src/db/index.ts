import fs from 'node:fs';
import path from 'node:path';
import Database from 'better-sqlite3';
import { config } from '../config';

/**
 * Conexão única com o banco, compartilhada pelo processo inteiro.
 *
 * better-sqlite3 é síncrono. Isso é intencional: não há callbacks nem await
 * espalhados pelo código de banco, o que deixa tudo muito mais fácil de ler
 * e de depurar. SQLite lê do disco local em microssegundos, então nada aqui
 * segura o servidor por tempo perceptível.
 */

let instancia: Database.Database | null = null;

export function db(): Database.Database {
  if (instancia) return instancia;

  const pasta = path.dirname(config.bancoCaminho);
  if (!fs.existsSync(pasta)) {
    fs.mkdirSync(pasta, { recursive: true });
  }

  const conexao = new Database(config.bancoCaminho);

  // WAL (write-ahead logging) permite que leituras aconteçam enquanto uma
  // escrita está em andamento. Sem isso, receber um relatório do Duplicati
  // bloquearia quem estivesse com o painel aberto no navegador.
  conexao.pragma('journal_mode = WAL');

  // Sem isto, o SQLite aceita silenciosamente um relatorios.cliente_id que
  // aponta para um cliente inexistente. Chaves estrangeiras são desligadas
  // por padrão no SQLite por compatibilidade histórica.
  conexao.pragma('foreign_keys = ON');

  instancia = conexao;
  return instancia;
}

/**
 * Colunas acrescentadas depois que a primeira versão do banco já existia.
 *
 * O `CREATE TABLE IF NOT EXISTS` do schema.sql cria a tabela nova completa,
 * mas NÃO mexe numa tabela que já existe — um banco em uso continuaria sem
 * as colunas novas, e toda gravação falharia. Cada entrada aqui é aplicada
 * uma única vez, conferindo antes se a coluna já está lá.
 *
 * Este é o mecanismo de migração do projeto. É simples de propósito:
 * acrescentar coluna cobre praticamente toda evolução de schema que um
 * painel como este precisa, e uma ferramenta de migração completa seria mais
 * peça para manter do que benefício.
 */
const COLUNAS_NOVAS: Array<{ tabela: string; coluna: string; tipo: string }> = [
  { tabela: 'relatorios', coluna: 'backup_nome', tipo: 'TEXT' },
  { tabela: 'relatorios', coluna: 'maquina_nome', tipo: 'TEXT' },
];

function aplicarColunasNovas(): void {
  const conexao = db();

  for (const { tabela, coluna, tipo } of COLUNAS_NOVAS) {
    const existe = conexao
      .prepare(`SELECT COUNT(*) AS n FROM pragma_table_info(?) WHERE name = ?`)
      .get(tabela, coluna) as { n: number };

    if (existe.n === 0) {
      conexao.exec(`ALTER TABLE ${tabela} ADD COLUMN ${coluna} ${tipo}`);
      console.log(`banco: coluna ${tabela}.${coluna} adicionada`);
    }
  }
}

/**
 * Cria as tabelas caso ainda não existam e aplica as colunas novas. Tudo é
 * idempotente, então chamar isto em toda inicialização é seguro.
 */
export function aplicarSchema(): void {
  const sql = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');
  db().exec(sql);
  aplicarColunasNovas();
}

/** Data e hora de agora em ISO 8601 UTC — o formato usado em todo o banco. */
export function agoraISO(): string {
  return new Date().toISOString();
}
