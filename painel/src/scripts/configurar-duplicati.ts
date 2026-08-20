import fs from 'node:fs';
import path from 'node:path';
import { aplicarSchema } from '../db';
import { listarClientes, type Cliente } from '../db/repo';

/**
 * Configura em lote o `send-http-json-urls` nos Duplicati dos cartórios.
 *
 *   npm run configurar-duplicati -- --modelo      cria o arquivo de servidores
 *   npm run configurar-duplicati -- --teste       mostra o que faria, sem mudar nada
 *   npm run configurar-duplicati                  aplica de verdade
 *
 * ---------------------------------------------------------------------------
 * COMO O DUPLICATI DECIDE PARA ONDE MANDAR O RELATÓRIO
 *
 * Existem dois lugares onde `send-http-json-urls` pode estar:
 *
 *   1. Opção padrão do SERVIDOR — vale para todos os backups daquele Duplicati
 *   2. Opção do BACKUP — vale só para aquele backup
 *
 * E aqui está o detalhe que decide o desenho deste script, verificado em
 * laboratório contra um Duplicati 2.3.0.4 real: quando os dois existem, o do
 * BACKUP SOBRESCREVE o do servidor. Não soma.
 *
 * Consequência: configurar só a opção do servidor deixaria de fora, em
 * silêncio, justamente os cartórios que já usam `send-http-json-urls` para
 * outra coisa. Eles apareceriam como "configurados" e nunca reportariam.
 *
 * Por isso o script faz as duas coisas:
 *
 *   - grava a opção padrão do servidor (cobre todos os backups comuns)
 *   - para cada backup que TEM opção própria, ACRESCENTA a URL do painel à
 *     lista dele, separada por ponto e vírgula, preservando o que já estava
 *
 * Nunca substituímos uma URL existente. Se um cartório manda relatório para
 * outro sistema, ele continua mandando.
 * ---------------------------------------------------------------------------
 */

const ARQUIVO_PADRAO = 'servidores.json';
const TEMPO_LIMITE_MS = 20_000;

const args = process.argv.slice(2);
const modoModelo = args.includes('--modelo');
const modoTeste = args.includes('--teste') || args.includes('--dry-run');
const aceitarCertificadoInvalido = args.includes('--inseguro');

function argumento(nome: string): string | undefined {
  const i = args.indexOf(`--${nome}`);
  return i === -1 ? undefined : args[i + 1];
}

const caminhoArquivo = path.resolve(argumento('arquivo') ?? ARQUIVO_PADRAO);

interface ServidorConfig {
  cartorioId: number;
  cartorio?: string;
  url: string;
  senha: string;
  /** Marque true para o script pular este servidor sem remover a linha. */
  pular?: boolean;
}

interface Arquivo {
  urlDoPainel: string;
  servidores: ServidorConfig[];
}

// ---------------------------------------------------------------------------
// MODO MODELO — gera o arquivo já preenchido com os cartórios do banco
// ---------------------------------------------------------------------------

function criarModelo(): void {
  aplicarSchema();
  const clientes = listarClientes().filter((c) => c.ativo);

  if (fs.existsSync(caminhoArquivo)) {
    console.error('');
    console.error(`  Já existe ${caminhoArquivo}.`);
    console.error('  Apague ou renomeie antes, para não perder as senhas já preenchidas.');
    console.error('');
    process.exit(1);
  }

  const modelo: Arquivo = {
    urlDoPainel: 'https://painel.chcom.com.br',
    servidores: clientes.map((c) => ({
      cartorioId: c.id,
      cartorio: c.nome,
      url: 'http://IP-DO-SERVIDOR:8200',
      senha: '',
    })),
  };

  fs.writeFileSync(caminhoArquivo, JSON.stringify(modelo, null, 2) + '\n', 'utf8');

  console.log('');
  console.log(`  Modelo criado: ${caminhoArquivo}`);
  console.log(`  ${clientes.length} cartório(s) ativo(s) já listado(s).`);
  console.log('');
  console.log('  Preencha "url" e "senha" de cada um, e ajuste "urlDoPainel".');
  console.log('');
  console.log('  ATENÇÃO: este arquivo vai conter as senhas dos Duplicati.');
  console.log('  Ele já está no .gitignore — não o commite e não o deixe em');
  console.log('  pasta compartilhada. Depois do onboarding, apague.');
  console.log('');
  process.exit(0);
}

if (modoModelo) criarModelo();

// ---------------------------------------------------------------------------
// LEITURA DO ARQUIVO
// ---------------------------------------------------------------------------

if (!fs.existsSync(caminhoArquivo)) {
  console.error('');
  console.error(`  Não encontrei ${caminhoArquivo}.`);
  console.error('  Rode primeiro:  npm run configurar-duplicati -- --modelo');
  console.error('');
  process.exit(1);
}

let config: Arquivo;
try {
  config = JSON.parse(fs.readFileSync(caminhoArquivo, 'utf8')) as Arquivo;
} catch (e) {
  console.error(`  ${caminhoArquivo} não é um JSON válido: ${(e as Error).message}`);
  process.exit(1);
}

if (!config.urlDoPainel || !Array.isArray(config.servidores)) {
  console.error('  O arquivo precisa ter "urlDoPainel" e a lista "servidores".');
  process.exit(1);
}

const urlDoPainel = config.urlDoPainel.replace(/\/+$/, '');

if (urlDoPainel.startsWith('http://') && !urlDoPainel.includes('localhost') && !urlDoPainel.includes('127.0.0.1')) {
  console.warn('');
  console.warn('  AVISO: urlDoPainel usa http:// sem TLS. Os relatórios de backup');
  console.warn('  vão trafegar em texto puro pela rede, e o token do cartório vai');
  console.warn('  junto na URL. Use https:// assim que o proxy estiver de pé.');
}

aplicarSchema();
const clientesPorId = new Map<number, Cliente>(listarClientes().map((c) => [c.id, c]));

// ---------------------------------------------------------------------------
// API DO DUPLICATI
// ---------------------------------------------------------------------------

const OPCAO = 'send-http-json-urls';
const CHAVE_GLOBAL = `--${OPCAO}`;

if (aceitarCertificadoInvalido) {
  // Alguns cartórios usam HTTPS com certificado autoassinado na rede interna.
  process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
}

async function chamar(
  base: string,
  caminho: string,
  opcoes: { metodo?: string; token?: string; corpo?: unknown } = {},
): Promise<unknown> {
  const controle = new AbortController();
  const timer = setTimeout(() => controle.abort(), TEMPO_LIMITE_MS);

  try {
    const resp = await fetch(`${base}${caminho}`, {
      method: opcoes.metodo ?? 'GET',
      headers: {
        ...(opcoes.token ? { Authorization: `Bearer ${opcoes.token}` } : {}),
        ...(opcoes.corpo !== undefined ? { 'Content-Type': 'application/json' } : {}),
      },
      body: opcoes.corpo !== undefined ? JSON.stringify(opcoes.corpo) : undefined,
      signal: controle.signal,
    });

    const texto = await resp.text();

    if (!resp.ok) {
      // A senha nunca entra na mensagem de erro, mesmo que a resposta do
      // servidor a mencione de alguma forma.
      throw new Error(`HTTP ${resp.status} em ${caminho}${texto ? ` — ${texto.slice(0, 160)}` : ''}`);
    }

    return texto ? JSON.parse(texto) : null;
  } finally {
    clearTimeout(timer);
  }
}

async function entrar(base: string, senha: string): Promise<string> {
  let r: { AccessToken?: string };
  try {
    r = (await chamar(base, '/api/v1/auth/login', {
      metodo: 'POST',
      corpo: { Password: senha },
    })) as { AccessToken?: string };
  } catch (e) {
    // O 401 aqui só pode ser senha errada, e vale traduzir: quem está
    // configurando 38 servidores não deveria precisar decifrar um código
    // HTTP para saber que errou a senha de um deles.
    if (e instanceof Error && e.message.includes('HTTP 401')) {
      throw new Error('SENHA_RECUSADA');
    }
    throw e;
  }

  if (!r?.AccessToken) throw new Error('SENHA_RECUSADA');
  return r.AccessToken;
}

/**
 * Traduz a falha para algo que diga o que fazer a seguir.
 *
 * As mensagens cruas do fetch ("fetch failed") e do AbortController
 * ("This operation was aborted") não ajudam ninguém a consertar nada.
 */
function explicar(e: unknown): string {
  const msg = e instanceof Error ? e.message : String(e);
  const causa = e instanceof Error && e.cause ? String((e.cause as { code?: string }).code ?? '') : '';

  if (msg === 'SENHA_RECUSADA') return 'senha recusada pelo Duplicati';
  if (e instanceof Error && e.name === 'AbortError')
    return `sem resposta em ${TEMPO_LIMITE_MS / 1000}s — servidor ligado mas travado?`;
  if (causa === 'ECONNREFUSED')
    return 'conexão recusada — Duplicati parado, ou porta errada';
  if (causa === 'ENOTFOUND' || causa === 'EAI_AGAIN')
    return 'endereço não resolvido — confira o nome ou o IP';
  if (causa === 'ETIMEDOUT' || causa === 'EHOSTUNREACH')
    return 'sem rota até o servidor — firewall ou VPN fora do ar?';
  if (msg.includes('certificate') || causa.includes('CERT'))
    return 'certificado TLS recusado — use --inseguro se for autoassinado';
  if (msg === 'fetch failed') return 'não foi possível conectar — confira IP, porta e firewall';
  return msg;
}

/**
 * Junta a URL do painel a uma lista existente, sem duplicar.
 * O Duplicati separa múltiplas URLs por ponto e vírgula.
 */
function juntarUrls(atual: string | null | undefined, nova: string): string | null {
  const partes = (atual ?? '')
    .split(';')
    .map((p) => p.trim())
    .filter((p) => p !== '');

  if (partes.includes(nova)) return null; // já está lá: nada a fazer
  partes.push(nova);
  return partes.join(';');
}

interface Resultado {
  cartorio: string;
  ok: boolean;
  global: 'gravada' | 'ja-estava' | 'erro' | 'nao-avaliada';
  backupsAjustados: string[];
  backupsJaOk: string[];
  detalhe?: string;
}

async function configurarServidor(s: ServidorConfig): Promise<Resultado> {
  const cliente = clientesPorId.get(s.cartorioId);
  const nome = cliente?.nome ?? s.cartorio ?? `cartório #${s.cartorioId}`;

  const res: Resultado = {
    cartorio: nome,
    ok: false,
    global: 'nao-avaliada',
    backupsAjustados: [],
    backupsJaOk: [],
  };

  if (!cliente) {
    res.detalhe = `cartório #${s.cartorioId} não existe no painel — cadastre antes`;
    return res;
  }
  if (!cliente.ativo) {
    res.detalhe = 'cartório está desativado no painel — o token seria recusado';
    return res;
  }
  if (!s.url || s.url.includes('IP-DO-SERVIDOR')) {
    res.detalhe = 'url não preenchida no arquivo';
    return res;
  }
  if (!s.senha) {
    res.detalhe = 'senha não preenchida no arquivo';
    return res;
  }

  const base = s.url.replace(/\/+$/, '');
  const urlRelatorio = `${urlDoPainel}/api/report/${cliente.token}`;

  const token = await entrar(base, s.senha);

  // ---- 1. opção padrão do servidor ----------------------------------------

  const settings = (await chamar(base, '/api/v1/serversettings', { token })) as Record<
    string,
    string | null
  >;

  const globalAtual = settings?.[CHAVE_GLOBAL] ?? '';
  const globalNova = juntarUrls(globalAtual, urlRelatorio);

  if (globalNova === null) {
    res.global = 'ja-estava';
  } else if (modoTeste) {
    res.global = 'gravada';
  } else {
    await chamar(base, '/api/v1/serversettings', {
      metodo: 'PATCH',
      token,
      corpo: { [CHAVE_GLOBAL]: globalNova },
    });
    res.global = 'gravada';
  }

  // ---- 2. backups que têm opção própria -----------------------------------
  //
  // Estes são o motivo de o script existir. A opção do backup vence a do
  // servidor, então sem tratá-los um a um eles continuariam mandando
  // relatório só para onde já mandavam, e o painel nunca saberia.

  const lista = (await chamar(base, '/api/v1/backups', { token })) as Array<{
    Backup?: { ID?: string; Name?: string };
  }>;

  for (const item of lista ?? []) {
    const id = item?.Backup?.ID;
    const nomeBackup = item?.Backup?.Name ?? `#${id}`;
    if (!id) continue;

    const detalhe = (await chamar(base, `/api/v1/backup/${id}`, { token })) as {
      Backup?: { Settings?: Array<{ Name: string; Value: string; Filter?: string }> };
    };

    const cfg = detalhe?.Backup;
    const settingsBackup = cfg?.Settings ?? [];

    // A opção pode aparecer com ou sem os dois hífens.
    const propria = settingsBackup.find(
      (o) => o.Name === CHAVE_GLOBAL || o.Name === OPCAO,
    );

    if (!propria) continue; // coberto pela opção do servidor

    const nova = juntarUrls(propria.Value, urlRelatorio);
    if (nova === null) {
      res.backupsJaOk.push(nomeBackup);
      continue;
    }

    if (!modoTeste) {
      propria.Value = nova;
      await chamar(base, `/api/v1/backup/${id}`, {
        metodo: 'PUT',
        token,
        corpo: detalhe,
      });
    }

    res.backupsAjustados.push(nomeBackup);
  }

  res.ok = true;
  return res;
}

// ---------------------------------------------------------------------------
// EXECUÇÃO
// ---------------------------------------------------------------------------

async function principal(): Promise<void> {
  const lista = config.servidores.filter((s) => !s.pular);

  console.log('');
  console.log(modoTeste ? '  MODO TESTE — nada será alterado' : '  APLICANDO ALTERAÇÕES');
  console.log(`  painel: ${urlDoPainel}`);
  console.log(`  ${lista.length} servidor(es) na lista`);
  console.log('');

  const resultados: Resultado[] = [];

  // Em série, de propósito: 38 servidores em paralelo produziriam um log
  // embaralhado, e se algo der errado no meio você quer saber exatamente
  // onde parou.
  for (const s of lista) {
    const nome = clientesPorId.get(s.cartorioId)?.nome ?? s.cartorio ?? `#${s.cartorioId}`;
    process.stdout.write(`  ${nome.padEnd(46).slice(0, 46)} `);

    try {
      const r = await configurarServidor(s);
      resultados.push(r);

      if (!r.ok) {
        console.log(`PULADO — ${r.detalhe}`);
      } else {
        const partes: string[] = [];
        partes.push(r.global === 'ja-estava' ? 'global já ok' : 'global gravada');
        if (r.backupsAjustados.length) partes.push(`${r.backupsAjustados.length} backup(s) ajustado(s)`);
        if (r.backupsJaOk.length) partes.push(`${r.backupsJaOk.length} já ok`);
        console.log(`OK — ${partes.join(', ')}`);
      }
    } catch (e) {
      const amigavel = explicar(e);
      console.log(`FALHOU — ${amigavel}`);
      resultados.push({
        cartorio: nome,
        ok: false,
        global: 'erro',
        backupsAjustados: [],
        backupsJaOk: [],
        detalhe: amigavel,
      });
    }
  }

  // ---- resumo -------------------------------------------------------------

  const oks = resultados.filter((r) => r.ok);
  const falhas = resultados.filter((r) => !r.ok);
  const comBackupProprio = oks.filter((r) => r.backupsAjustados.length > 0);

  console.log('');
  console.log('  ' + '-'.repeat(60));
  console.log(`  ${oks.length} configurado(s), ${falhas.length} com problema`);

  if (comBackupProprio.length > 0) {
    console.log('');
    console.log('  Backups que já tinham send-http-json-urls próprio, e onde a');
    console.log('  URL do painel foi ACRESCENTADA (a de vocês foi preservada):');
    for (const r of comBackupProprio) {
      console.log(`    ${r.cartorio}: ${r.backupsAjustados.join(', ')}`);
    }
  }

  if (falhas.length > 0) {
    console.log('');
    console.log('  Precisam de atenção:');
    for (const r of falhas) console.log(`    ${r.cartorio} — ${r.detalhe}`);
  }

  console.log('');
  if (modoTeste) {
    console.log('  Nada foi alterado. Para aplicar, rode sem --teste.');
  } else {
    console.log('  Pronto. A configuração vale a partir do PRÓXIMO backup de cada');
    console.log('  cartório — nada é enviado retroativamente. Confira no painel');
    console.log('  amanhã, ou dispare um backup manual para testar agora.');
  }
  console.log('');

  process.exit(falhas.length > 0 ? 1 : 0);
}

principal().catch((e) => {
  console.error('');
  console.error(`  Erro inesperado: ${e instanceof Error ? e.message : String(e)}`);
  console.error('');
  process.exit(1);
});
