import { config } from '../config';

/**
 * Formatação para leitura humana, em português do Brasil.
 */

/**
 * Escapa texto que vai para dentro do HTML.
 *
 * Nomes de cartório e mensagens de erro do Duplicati vêm do banco e vão
 * direto para a página. Sem escapar, um nome com `<` quebraria o layout, e
 * um relatório contendo `<script>` executaria no navegador de quem abrisse o
 * painel. Como este projeto monta HTML com template string em vez de usar um
 * motor de templates (que escaparia sozinho), escapar é responsabilidade
 * nossa — TODO valor vindo do banco tem que passar por aqui.
 */
export function esc(valor: unknown): string {
  if (valor === null || valor === undefined) return '';
  return String(valor)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Bytes para leitura humana.
 *
 * Base 1024, com os rótulos KB/MB/GB/TB — é a mesma convenção que o Windows
 * usa, então o número aqui bate com o que você vê no Explorer do servidor do
 * cartório. Note que a AWS fatura em base 1000, então o valor de referência
 * para custo é um pouco maior que o mostrado aqui.
 */
export function bytes(valor: number | null | undefined): string {
  if (valor === null || valor === undefined) return '—';
  if (!Number.isFinite(valor)) return '—';
  if (valor === 0) return '0 B';

  const unidades = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  const i = Math.min(
    Math.floor(Math.log(Math.abs(valor)) / Math.log(1024)),
    unidades.length - 1,
  );
  const n = valor / Math.pow(1024, i);
  const casas = n < 10 && i > 0 ? 2 : n < 100 && i > 0 ? 1 : 0;

  return `${n.toLocaleString('pt-BR', {
    minimumFractionDigits: casas,
    maximumFractionDigits: casas,
  })} ${unidades[i]}`;
}

/**
 * Data e hora no fuso de exibição.
 *
 * O banco guarda tudo em UTC, que é o certo para armazenar. Mas mostrar UTC
 * na tela faria um backup das 3h da manhã em Porto Velho aparecer como 7h —
 * e você concluiria que o agendamento está errado quando não está.
 */
export function dataHora(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';

  return new Intl.DateTimeFormat('pt-BR', {
    timeZone: config.fusoExibicao,
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(d);
}

/** Só a data, sem hora. */
export function dataCurta(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';

  return new Intl.DateTimeFormat('pt-BR', {
    timeZone: config.fusoExibicao,
    day: '2-digit',
    month: '2-digit',
    year: '2-digit',
  }).format(d);
}

/** Duração em segundos para "4 min 12 s" / "1 h 06 min". */
export function duracao(segundos: number | null | undefined): string {
  if (segundos === null || segundos === undefined) return '—';
  if (!Number.isFinite(segundos) || segundos < 0) return '—';

  // "0 s" lê como se nada tivesse acontecido. Um backup que levou meio
  // segundo aconteceu — só foi rápido.
  if (segundos < 1) return 'menos de 1 s';
  if (segundos < 60) return `${Math.round(segundos)} s`;

  const h = Math.floor(segundos / 3600);
  const m = Math.floor((segundos % 3600) / 60);
  const s = Math.round(segundos % 60);

  if (h > 0) return `${h} h ${String(m).padStart(2, '0')} min`;
  return `${m} min ${String(s).padStart(2, '0')} s`;
}

/**
 * Data por extenso, com "hoje" e "ontem" quando cabe.
 *
 *   hoje às 19:17
 *   ontem às 21:45
 *   quinta-feira, 15 de janeiro de 2026, 22:02
 *
 * O "hoje/ontem" é calculado no fuso de exibição, não no do servidor. Um
 * backup das 22h em Porto Velho é 2h do dia seguinte em UTC — comparar as
 * datas em UTC faria o backup de ontem à noite aparecer como "hoje".
 */
export function dataPorExtenso(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';

  const hora = new Intl.DateTimeFormat('pt-BR', {
    timeZone: config.fusoExibicao,
    hour: '2-digit',
    minute: '2-digit',
  }).format(d);

  // "2026-08-13" no fuso de exibição, para comparar dias sem ambiguidade.
  const diaDe = (x: Date) =>
    new Intl.DateTimeFormat('en-CA', {
      timeZone: config.fusoExibicao,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(x);

  const agora = new Date();
  const ontem = new Date(agora.getTime() - 86400_000);

  if (diaDe(d) === diaDe(agora)) return `hoje às ${hora}`;
  if (diaDe(d) === diaDe(ontem)) return `ontem às ${hora}`;

  const completa = new Intl.DateTimeFormat('pt-BR', {
    timeZone: config.fusoExibicao,
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  }).format(d);

  return `${completa}, ${hora}`;
}

/**
 * Velocidade média da transferência, em bits por segundo.
 *
 * Redes são medidas em BITS (Mbps) e arquivos em BYTES (MB) — daí o ×8. É a
 * confusão mais comum do ramo: um link de 100 Mbps entrega no máximo uns
 * 12 MB/s, e quem espera 100 MB/s conclui que a operadora está roubando.
 */
export function velocidade(
  bytes: number | null | undefined,
  segundos: number | null | undefined,
): string {
  if (!bytes || !segundos || segundos <= 0 || bytes <= 0) return '—';

  const bits = bytes * 8;
  const bps = bits / segundos;

  const unidades = ['bps', 'Kbps', 'Mbps', 'Gbps'];
  const i = Math.min(
    Math.floor(Math.log(bps) / Math.log(1000)),
    unidades.length - 1,
  );
  const n = bps / Math.pow(1000, i);

  return `${n.toLocaleString('pt-BR', {
    minimumFractionDigits: n < 10 ? 1 : 0,
    maximumFractionDigits: n < 10 ? 1 : 0,
  })} ${unidades[i]}`;
}

/** "há 3 horas", "há 2 dias" — para saber num relance se o backup atrasou. */
export function tempoDesde(iso: string | null | undefined): string {
  if (!iso) return 'nunca';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';

  const segundos = (Date.now() - d.getTime()) / 1000;
  if (segundos < 0) return 'agora';
  if (segundos < 60) return 'agora mesmo';
  if (segundos < 3600) {
    const m = Math.floor(segundos / 60);
    return `há ${m} ${m === 1 ? 'minuto' : 'minutos'}`;
  }
  if (segundos < 86400) {
    const h = Math.floor(segundos / 3600);
    return `há ${h} ${h === 1 ? 'hora' : 'horas'}`;
  }
  const dias = Math.floor(segundos / 86400);
  return `há ${dias} ${dias === 1 ? 'dia' : 'dias'}`;
}

export function numero(valor: number | null | undefined): string {
  if (valor === null || valor === undefined) return '—';
  return valor.toLocaleString('pt-BR');
}

/** Horas desde um instante. Null quando não há data válida. */
export function horasDesde(iso: string | null | undefined): number | null {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  return (Date.now() - d.getTime()) / 3600000;
}

/**
 * Backup que PAROU de acontecer é a falha mais perigosa deste sistema, e a
 * única que o painel não enxergava.
 *
 * O último relatório de um cartório assim diz "Sucesso" — e continua dizendo
 * isso para sempre, porque não chega relatório novo para contradizê-lo. O
 * cartório fica verde no painel enquanto há dias não se faz backup nenhum.
 * Uma falha que grita aparece; esta some.
 *
 * Por isso a IDADE do último relatório vira situação própria, não um detalhe
 * da coluna de data.
 *
 * O limite parte de backup diário, que é o caso dos cartórios: até 26 horas
 * está em dia (24 mais folga para atraso de horário e fuso), até 48 está
 * atrasado, acima disso está parado. Se algum cartório passar a rodar
 * semanalmente, isto precisa virar configuração por cartório — hoje ele
 * apareceria como parado todo dia.
 */
export const HORAS_ATRASADO = 26;
export const HORAS_PARADO = 48;

export type Atraso = 'em-dia' | 'atrasado' | 'parado' | 'nunca';

export function atrasoDe(iso: string | null | undefined): Atraso {
  const h = horasDesde(iso);
  if (h === null) return 'nunca';
  if (h > HORAS_PARADO) return 'parado';
  if (h > HORAS_ATRASADO) return 'atrasado';
  return 'em-dia';
}

export const ROTULO_ATRASO: Record<Atraso, string> = {
  'em-dia': 'em dia',
  atrasado: 'atrasado',
  parado: 'parado',
  nunca: 'nunca reportou',
};

/** Situação do cartório, derivada do último relatório recebido. */
export type Situacao = 'ok' | 'aviso' | 'erro' | 'sem-dados';

export function situacaoDe(resultado: string | null | undefined): Situacao {
  if (!resultado) return 'sem-dados';
  const r = resultado.toLowerCase();
  if (r === 'success') return 'ok';
  if (r === 'warning') return 'aviso';
  if (r === 'error' || r === 'fatal') return 'erro';
  // Um resultado que não reconhecemos não é um sucesso. Tratar o
  // desconhecido como "ok" pintaria de verde um backup que pode ter
  // falhado de um jeito novo.
  return 'aviso';
}

export const ROTULO_SITUACAO: Record<Situacao, string> = {
  ok: 'Sucesso',
  aviso: 'Aviso',
  erro: 'Falha',
  'sem-dados': 'Nunca reportou',
};
