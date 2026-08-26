import { Router, type Request } from 'express';
import {
  buscarClientePorToken,
  registrarRecusa,
  salvarExecucaoDoCofre,
  type ExecucaoDoCofre,
  type ItemDoCofre,
} from '../db/repo';

export const rotaCofre = Router();

/** Mesmo formato do token do Duplicati: 32 hexadecimais. */
const FORMATO_TOKEN = /^[0-9a-f]{32}$/;

/** Versão do formato que este código sabe ler. */
export const VERSAO_COFRE = 1;

function ipDe(req: Request): string | null {
  const encaminhado = req.headers['x-forwarded-for'];
  if (typeof encaminhado === 'string' && encaminhado.trim() !== '') {
    return encaminhado.split(',')[0]!.trim();
  }
  return req.ip ?? null;
}

/**
 * Lê um campo que pode vir com qualquer capitalização.
 *
 * O agente é PowerShell e manda `Cartorio`, `Maquina`, `Resultado`. Um cliente
 * futuro — ou um teste feito com curl — pode mandar minúsculo. Aceitar as duas
 * formas custa três linhas e evita a classe de defeito mais chata deste tipo
 * de integração: o relatório chega, é aceito, e grava tudo nulo.
 */
function campo(obj: Record<string, unknown>, nome: string): unknown {
  if (nome in obj) return obj[nome];
  const alvo = nome.toLowerCase();
  for (const chave of Object.keys(obj)) {
    if (chave.toLowerCase() === alvo) return obj[chave];
  }
  return undefined;
}

function texto(v: unknown): string | null {
  if (typeof v === 'string' && v.trim() !== '') return v;
  return null;
}

function numero(v: unknown): number {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string') {
    const n = Number(v);
    if (Number.isFinite(n)) return n;
  }
  return 0;
}

function booleano(v: unknown): boolean {
  if (typeof v === 'boolean') return v;
  // O PowerShell serializa como `true`/`false`, mas JSON escrito à mão às
  // vezes traz "True" ou 1.
  if (typeof v === 'string') return v.toLowerCase() === 'true';
  if (typeof v === 'number') return v !== 0;
  return false;
}

/**
 * Converte o JSON do agente no que vai para o banco.
 *
 * Nada aqui recusa o relatório. Campo faltando vira nulo ou zero, e o
 * `json_bruto` guarda o original inteiro — recusar um relatório porque o
 * formato mudou seria jogar fora justamente a evidência de que mudou.
 */
export function lerExecucao(json: unknown): ExecucaoDoCofre {
  const raiz = (typeof json === 'object' && json !== null ? json : {}) as Record<
    string,
    unknown
  >;

  const detalhes: ItemDoCofre[] = [];
  const lista = campo(raiz, 'Detalhes');
  if (Array.isArray(lista)) {
    for (const bruto of lista) {
      if (typeof bruto !== 'object' || bruto === null) continue;
      const item = bruto as Record<string, unknown>;
      detalhes.push({
        tipo: texto(campo(item, 'Tipo')) ?? 'desconhecido',
        nome: texto(campo(item, 'Nome')) ?? '(sem nome)',
        sucesso: booleano(campo(item, 'Sucesso')),
        consistencia: texto(campo(item, 'Consistencia')),
        bytes: numero(campo(item, 'Bytes')),
        quando: texto(campo(item, 'Quando')),
      });
    }
  }

  return {
    // O nome da máquina é obrigatório na prática: sem ele, o host e as VMs de
    // um mesmo cartório viram uma pilha só. Quando não vier, fica explícito
    // em vez de virar string vazia silenciosa.
    maquina: texto(campo(raiz, 'Maquina')) ?? '(maquina não informada)',
    comecouEm: texto(campo(raiz, 'Comecou')),
    terminouEm: texto(campo(raiz, 'Terminou')),
    resultado: texto(campo(raiz, 'Resultado')),
    itens: numero(campo(raiz, 'Itens')),
    sucessos: numero(campo(raiz, 'Sucessos')),
    falhas: numero(campo(raiz, 'Falhas')),
    detalhes,
  };
}

/**
 * POST /api/cofre/:token
 *
 * É o endereço que o CH.Com Cofre chama ao fim de cada execução. O mesmo
 * token do cartório serve para os dois produtos — o Duplicati manda em
 * /api/report, o Cofre manda aqui — e é por isso que as duas rotas ficam
 * separadas: o formato é diferente, e forçar um no outro faria as colunas
 * mentirem.
 *
 * O corpo chega como TEXTO CRU, pelo mesmo motivo da rota do Duplicati: se o
 * agente mandar um Content-Type diferente do esperado, o `express.json()`
 * entregaria corpo vazio e o relatório se perderia em silêncio — a pior
 * falha possível num sistema de monitoramento.
 *
 * O QUE NÃO CHEGA AQUI, E É DE PROPÓSITO
 *
 * Nem a chave de criptografia, nem a credencial da AWS, nem nome de arquivo
 * do cliente. O painel precisa saber SE o backup existe, não o que tem
 * dentro. O agente já manda só o resumo.
 */
rotaCofre.post('/api/cofre/:token', (req, res) => {
  const token = req.params.token ?? '';
  const ip = ipDe(req);
  const corpo = typeof req.body === 'string' ? req.body : '';

  if (!FORMATO_TOKEN.test(token)) {
    registrarRecusa({
      tokenUsado: token.slice(0, 100),
      motivo: 'cofre: token com formato inválido',
      ipOrigem: ip,
      corpoBruto: corpo,
    });
    return res.status(401).json({ ok: false, erro: 'token inválido' });
  }

  const cliente = buscarClientePorToken(token);
  if (!cliente) {
    registrarRecusa({
      tokenUsado: token,
      motivo: 'cofre: token não cadastrado',
      ipOrigem: ip,
      corpoBruto: corpo,
    });
    return res.status(401).json({ ok: false, erro: 'token inválido' });
  }

  if (!cliente.ativo) {
    registrarRecusa({
      tokenUsado: token,
      motivo: `cofre: cliente desativado (${cliente.nome})`,
      ipOrigem: ip,
      corpoBruto: corpo,
    });
    return res.status(403).json({ ok: false, erro: 'cliente desativado' });
  }

  if (corpo.trim() === '') {
    registrarRecusa({
      tokenUsado: token,
      motivo: 'cofre: corpo vazio',
      ipOrigem: ip,
      corpoBruto: null,
    });
    return res.status(400).json({ ok: false, erro: 'corpo vazio' });
  }

  let json: unknown;
  try {
    json = JSON.parse(corpo);
  } catch {
    registrarRecusa({
      tokenUsado: token,
      motivo: 'cofre: corpo não é JSON válido',
      ipOrigem: ip,
      corpoBruto: corpo,
    });
    return res.status(400).json({ ok: false, erro: 'corpo não é JSON válido' });
  }

  const execucao = lerExecucao(json);

  const execucaoId = salvarExecucaoDoCofre(
    cliente.id,
    execucao,
    corpo,
    VERSAO_COFRE,
  );

  // Falha de item vai para o console do painel. Num parque de 50 cartórios é
  // o primeiro lugar onde alguém olha quando algo some — e uma VM que falhou
  // não pode depender de ninguém abrir a tela para ser notada.
  const falhados = execucao.detalhes.filter((d) => !d.sucesso);
  if (falhados.length > 0) {
    console.warn(
      `[cofre ${execucaoId}] ${cliente.nome} / ${execucao.maquina}: ` +
        `${falhados.length} item(ns) falharam: ${falhados.map((f) => f.nome).join(', ')}`,
    );
  }

  // Um item que subiu como crash-consistent é verde no relatório, mas não é a
  // mesma coisa que application-consistent: significa que a VM foi copiada
  // como se tivesse faltado energia. Costuma restaurar, mas não há promessa —
  // e isso merece aparecer sem ninguém precisar procurar.
  const semPromessa = execucao.detalhes.filter(
    (d) => d.sucesso && (d.consistencia ?? '').toUpperCase().includes('CRASH'),
  );
  if (semPromessa.length > 0) {
    console.warn(
      `[cofre ${execucaoId}] ${cliente.nome} / ${execucao.maquina}: ` +
        `${semPromessa.length} item(ns) CRASH-CONSISTENT: ${semPromessa.map((f) => f.nome).join(', ')}`,
    );
  }

  return res.status(200).json({
    ok: true,
    execucaoId,
    cliente: { id: cliente.id, nome: cliente.nome, cidade: cliente.cidade },
    recebido: {
      maquina: execucao.maquina,
      resultado: execucao.resultado,
      itens: execucao.itens,
      sucessos: execucao.sucessos,
      falhas: execucao.falhas,
      detalhes: execucao.detalhes.length,
    },
  });
});
