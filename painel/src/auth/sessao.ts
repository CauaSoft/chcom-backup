import crypto from 'node:crypto';
import type { NextFunction, Request, Response } from 'express';
import {
  apagarSessao,
  buscarSessao,
  criarSessao,
  limparSessoesVencidas,
} from '../db/repo';

/**
 * Sessão por cookie, guardada no banco.
 *
 * Sem express-session, sem cookie-parser: são poucas linhas e evitam duas
 * dependências num projeto que precisa ser fácil de manter sozinho.
 */

export const NOME_COOKIE = 'painel_sessao';

/** Quanto tempo a sessão dura sem precisar entrar de novo. */
const DURACAO_HORAS = 12;

/** Informação do usuário logado, anexada à requisição pelo middleware. */
export interface Sessao {
  id: string;
  adminId: number;
  usuario: string;
}

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      sessao?: Sessao;
    }
  }
}

function lerCookies(req: Request): Record<string, string> {
  const cabecalho = req.headers.cookie;
  if (!cabecalho) return {};

  const saida: Record<string, string> = {};
  for (const parte of cabecalho.split(';')) {
    const igual = parte.indexOf('=');
    if (igual < 1) continue;
    const nome = parte.slice(0, igual).trim();
    const valor = parte.slice(igual + 1).trim();
    try {
      saida[nome] = decodeURIComponent(valor);
    } catch {
      saida[nome] = valor;
    }
  }
  return saida;
}

function ehHttps(req: Request): boolean {
  return req.protocol === 'https';
}

export function abrirSessao(
  req: Request,
  res: Response,
  adminId: number,
): string {
  // 256 bits de aleatoriedade criptográfica. É o valor que autentica o
  // usuário a cada requisição — precisa ser impossível de adivinhar.
  const id = crypto.randomBytes(32).toString('hex');
  const expira = new Date(Date.now() + DURACAO_HORAS * 3600_000);

  criarSessao(id, adminId, expira.toISOString(), req.ip ?? null);

  res.cookie(NOME_COOKIE, id, {
    // HttpOnly: JavaScript da página não consegue ler o cookie. Se algum dia
    // entrar um XSS no painel, o atacante ainda não leva a sessão.
    httpOnly: true,

    // SameSite Lax: o navegador não manda este cookie em POST vindo de outro
    // site. É o que impede um site malicioso de fazer seu navegador logado
    // cadastrar ou desativar cartórios sem você saber (CSRF).
    sameSite: 'lax',

    // Só manda por HTTPS quando a conexão já é HTTPS. Em desenvolvimento,
    // via http://localhost, o cookie precisa funcionar sem isso.
    secure: ehHttps(req),

    expires: expira,
    path: '/',
  });

  return id;
}

export function fecharSessao(req: Request, res: Response): void {
  const id = lerCookies(req)[NOME_COOKIE];
  if (id) apagarSessao(id);
  res.clearCookie(NOME_COOKIE, { path: '/' });
}

/**
 * Lê a sessão do cookie e anexa em req.sessao, se houver uma válida.
 * Não bloqueia nada — quem bloqueia é o exigirLogin.
 */
export function carregarSessao(
  req: Request,
  _res: Response,
  next: NextFunction,
): void {
  const id = lerCookies(req)[NOME_COOKIE];
  if (id) {
    const s = buscarSessao(id);
    if (s) {
      req.sessao = { id, adminId: s.admin_id, usuario: s.usuario };
    }
  }
  next();
}

/**
 * Exige login. Navegador vai para a tela de entrada; API recebe 401.
 *
 * O endereço original vai como `destino` na URL, para que entrar leve a
 * pessoa de volta ao que ela tentou abrir, em vez de despejá-la na home.
 */
export function exigirLogin(
  req: Request,
  res: Response,
  next: NextFunction,
): void {
  if (req.sessao) return next();

  if (req.accepts('html') && req.method === 'GET') {
    const destino = encodeURIComponent(req.originalUrl);
    res.redirect(`/entrar?destino=${destino}`);
    return;
  }

  res.status(401).json({ ok: false, erro: 'não autenticado' });
}

/**
 * Barra POST de formulário que venha de outro site.
 *
 * O SameSite=Lax do cookie já é a defesa principal contra CSRF. Esta é a
 * segunda camada, para o caso de um navegador antigo que não respeite
 * SameSite: se o cabeçalho Origin vier e não for o nosso host, recusa.
 *
 * Não vale para POST /api/report — o Duplicati não manda Origin, e não deve
 * mesmo: aquela rota é autenticada por token, não por cookie, então não é
 * alvo de CSRF.
 */
export function conferirOrigem(
  req: Request,
  res: Response,
  next: NextFunction,
): void {
  const origem = req.headers.origin;
  if (!origem) return next(); // navegação normal de formulário pode não mandar

  let hostOrigem: string;
  try {
    hostOrigem = new URL(origem).host;
  } catch {
    res.status(403).send('Origem inválida.');
    return;
  }

  if (hostOrigem !== req.get('host')) {
    res.status(403).send('Requisição vinda de outro site foi recusada.');
    return;
  }

  next();
}

/**
 * Proteção contra força bruta no login.
 *
 * Contador em memória por IP. Perder isso num reinício é aceitável: um
 * atacante não controla quando o servidor reinicia, e guardar no banco
 * significaria uma escrita por tentativa — o que transformaria o próprio
 * mecanismo de defesa num jeito de encher o disco.
 */
const tentativas = new Map<string, { contagem: number; ate: number }>();

const LIMITE = 8;
const JANELA_MS = 15 * 60_000;

export function podeTentar(ip: string): { pode: boolean; faltamSegundos: number } {
  const reg = tentativas.get(ip);
  if (!reg) return { pode: true, faltamSegundos: 0 };

  if (Date.now() > reg.ate) {
    tentativas.delete(ip);
    return { pode: true, faltamSegundos: 0 };
  }

  if (reg.contagem < LIMITE) return { pode: true, faltamSegundos: 0 };

  return {
    pode: false,
    faltamSegundos: Math.ceil((reg.ate - Date.now()) / 1000),
  };
}

export function registrarFalha(ip: string): void {
  const reg = tentativas.get(ip);
  if (!reg || Date.now() > reg.ate) {
    tentativas.set(ip, { contagem: 1, ate: Date.now() + JANELA_MS });
    return;
  }
  reg.contagem++;
  reg.ate = Date.now() + JANELA_MS;
}

export function limparFalhas(ip: string): void {
  tentativas.delete(ip);
}

/**
 * Faxina periódica das sessões vencidas. Uma vez por hora é suficiente: as
 * sessões vencidas já são recusadas na consulta, isto só evita a tabela
 * crescer sem limite.
 */
export function agendarLimpezaDeSessoes(): NodeJS.Timeout {
  const t = setInterval(
    () => {
      try {
        const n = limparSessoesVencidas();
        if (n > 0) console.log(`sessões vencidas removidas: ${n}`);
      } catch (e) {
        console.error('falha ao limpar sessões:', e);
      }
    },
    3600_000,
  );

  // unref: este temporizador não deve segurar o processo vivo na hora de
  // encerrar o servidor.
  t.unref();
  return t;
}
